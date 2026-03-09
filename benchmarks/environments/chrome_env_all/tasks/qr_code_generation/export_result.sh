#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome QR Code Generation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Create verification directory
VERIFY_DIR="/tmp/qr_code_verification"
mkdir -p "$VERIFY_DIR"

# Export Downloads folder contents information
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Examining Downloads folder..."

if [ -d "$DOWNLOADS_DIR" ]; then
    # List all PNG files with details
    find "$DOWNLOADS_DIR" -name "*.png" -type f -printf "%T@ %s %p\n" 2>/dev/null | sort -rn > "$VERIFY_DIR/downloads_list.txt" || true
    
    # Count PNG files
    PNG_COUNT=$(find "$DOWNLOADS_DIR" -name "*.png" -type f 2>/dev/null | wc -l)
    echo "Found $PNG_COUNT PNG file(s) in Downloads"
    
    # Copy recently created PNG files (created in last 5 minutes)
    echo "Copying recent PNG files to verification directory..."
    find "$DOWNLOADS_DIR" -name "*.png" -type f -mmin -5 -exec cp {} "$VERIFY_DIR/" \; 2>/dev/null || true
    
    # List all files for debugging
    echo "Downloads folder contents:"
    ls -lah "$DOWNLOADS_DIR" || true
else
    echo "⚠ Warning: Downloads folder not found"
fi

# Record task completion timestamp
date +%s > "$VERIFY_DIR/task_end_timestamp.txt"

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification info to /tmp root for easy access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files prepared in: $VERIFY_DIR"