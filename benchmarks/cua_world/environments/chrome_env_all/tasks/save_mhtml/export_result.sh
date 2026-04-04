#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Save MHTML Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure any pending save operations complete
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 2

# Create verification directory
VERIFY_DIR="/tmp/mhtml_verification"
mkdir -p "$VERIFY_DIR"

# Look for MHTML files in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for MHTML files in Downloads folder..."

# Find any MHTML/MHT files created recently (last 5 minutes)
RECENT_MHTML=$(find "$DOWNLOADS_DIR" -type f \( -name "*.mhtml" -o -name "*.mht" \) -mmin -5 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

if [ -n "$RECENT_MHTML" ] && [ -f "$RECENT_MHTML" ]; then
    MHTML_NAME=$(basename "$RECENT_MHTML")
    echo "✓ Found MHTML file: $MHTML_NAME"
    
    # Copy to verification directory
    cp "$RECENT_MHTML" "$VERIFY_DIR/"
    echo "$MHTML_NAME" > "$VERIFY_DIR/mhtml_filename.txt"
    
    # Get file size for logging
    FILE_SIZE=$(stat -c "%s" "$RECENT_MHTML" 2>/dev/null || echo "unknown")
    echo "File size: $FILE_SIZE bytes"
    echo "$FILE_SIZE" > "$VERIFY_DIR/mhtml_filesize.txt"
    
    # Get first 2KB of file for format validation
    head -c 2048 "$RECENT_MHTML" > "$VERIFY_DIR/mhtml_header.txt" 2>/dev/null || true
    
    ls -lh "$RECENT_MHTML"
else
    echo "⚠ No MHTML file found in Downloads folder"
    echo "none" > "$VERIFY_DIR/mhtml_filename.txt"
    
    # List all files in Downloads for debugging
    echo "Contents of Downloads folder:"
    ls -lah "$DOWNLOADS_DIR" || true
    ls -lah "$DOWNLOADS_DIR" > "$VERIFY_DIR/downloads_listing.txt" 2>/dev/null || true
fi

# Capture active tab URL via CDP for context
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "Active title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification info to standard temp location for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $VERIFY_DIR"