#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome QR Code Generation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure downloads are complete
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Wait a moment for any pending downloads to complete
sleep 2

# Create temporary verification directory
VERIFY_DIR="/tmp/qr_code_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab URL via CDP for verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
fi

# Search for QR code image in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for QR code image in: $DOWNLOADS_DIR"

# Find the most recent PNG file that matches QR code patterns
QR_FILE=""

# Try various QR code filename patterns (most specific first)
for pattern in "qrcode*.png" "*QR*.png" "*_qr.png" "wikipedia*.png"; do
    FOUND=$(find "$DOWNLOADS_DIR" -name "$pattern" -type f -mmin -5 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || echo "")
    if [ -n "$FOUND" ] && [ -f "$FOUND" ]; then
        QR_FILE="$FOUND"
        echo "✓ Found QR code image: $(basename "$QR_FILE")"
        break
    fi
done

# If no match, try finding any recent PNG (fallback)
if [ -z "$QR_FILE" ]; then
    echo "No QR-specific filename found, searching for recent PNG files..."
    QR_FILE=$(find "$DOWNLOADS_DIR" -name "*.png" -type f -mmin -5 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || echo "")
fi

if [ -n "$QR_FILE" ] && [ -f "$QR_FILE" ]; then
    echo "✓ Found potential QR code: $QR_FILE"
    
    # Copy to verification directory
    cp "$QR_FILE" "$VERIFY_DIR/qr_code.png"
    echo "$(basename "$QR_FILE")" > "$VERIFY_DIR/qr_filename.txt"
    
    # Get file info
    ls -lh "$QR_FILE"
    
    # Check file size
    FILE_SIZE=$(stat -f%z "$QR_FILE" 2>/dev/null || stat -c%s "$QR_FILE" 2>/dev/null || echo "0")
    echo "File size: $FILE_SIZE bytes"
    echo "$FILE_SIZE" > "$VERIFY_DIR/qr_filesize.txt"
else
    echo "⚠ No QR code image found in Downloads folder"
    echo "none" > "$VERIFY_DIR/qr_filename.txt"
    echo "0" > "$VERIFY_DIR/qr_filesize.txt"
    
    # List all files in Downloads for debugging
    echo "Contents of Downloads folder:"
    ls -lah "$DOWNLOADS_DIR" 2>/dev/null || echo "Could not list Downloads folder"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy all verification files to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files copied to: $VERIFY_DIR"