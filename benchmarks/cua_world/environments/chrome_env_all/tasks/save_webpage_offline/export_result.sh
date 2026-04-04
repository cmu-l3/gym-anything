#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Save Webpage Offline Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Give Chrome extra time to complete any ongoing file operations
echo "Waiting for file operations to complete..."
sleep 3

# Capture active tab URL via CDP for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# List Downloads folder contents for debugging
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Contents of Downloads folder:"
ls -lAh "$DOWNLOADS_DIR" 2>/dev/null || echo "Could not list Downloads folder"

# Look for recently created HTML files and folders
echo ""
echo "Recent HTML files in Downloads (last 10 minutes):"
find "$DOWNLOADS_DIR" -name "*.html" -o -name "*.htm" -type f -mmin -10 2>/dev/null | while read file; do
    echo "  HTML: $file"
    ls -lh "$file"
done

echo ""
echo "Recent resource folders (_files) in Downloads:"
find "$DOWNLOADS_DIR" -name "*_files" -type d -mmin -10 2>/dev/null | while read dir; do
    echo "  Folder: $dir"
    file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
    echo "    Contains $file_count files"
done

echo "✅ Export complete"
echo "Verifier will analyze saved files in Downloads folder"