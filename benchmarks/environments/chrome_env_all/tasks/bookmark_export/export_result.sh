#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Export Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for debugging
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Give Chrome a moment to complete any ongoing file operations
sleep 2

# Gracefully close Chrome to ensure all files are flushed to disk
echo "Closing Chrome to ensure file operations complete..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Search for exported bookmark HTML files in Downloads
echo "Searching for exported bookmark HTML file..."
DOWNLOADS_DIR="/home/ga/Downloads"

# Look for HTML files created in the last 5 minutes
if [ -d "$DOWNLOADS_DIR" ]; then
    echo "Contents of Downloads directory:"
    ls -lah "$DOWNLOADS_DIR" || true
    
    # Find recent HTML files
    RECENT_HTML=$(find "$DOWNLOADS_DIR" -name "*.html" -type f -mmin -5 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -n "$RECENT_HTML" ] && [ -f "$RECENT_HTML" ]; then
        HTML_NAME=$(basename "$RECENT_HTML")
        echo "✓ Found recent HTML file: $HTML_NAME"
        
        # Copy to standard location for verification
        cp "$RECENT_HTML" /tmp/exported_bookmarks.html
        echo "$HTML_NAME" > /tmp/bookmark_filename.txt
        
        # Show first few lines for debugging
        echo "First 10 lines of exported file:"
        head -n 10 "$RECENT_HTML" || true
    else
        echo "⚠ No recent HTML file found in Downloads"
        echo "none" > /tmp/bookmark_filename.txt
    fi
else
    echo "⚠ Downloads directory not found"
    echo "none" > /tmp/bookmark_filename.txt
fi

# Also copy the original Bookmarks file for comparison
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" /tmp/original_bookmarks.json
    echo "Original bookmarks copied for verification"
fi

echo "✅ Export complete"