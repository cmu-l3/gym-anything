#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Export Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure any unsaved state is committed
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure any buffered file operations complete
echo "Closing Chrome to ensure export is complete..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Look for exported HTML file in Downloads
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for exported bookmark file in Downloads..."

# Check for the expected filename
if [ -f "$DOWNLOADS_DIR/bookmarks_backup.html" ]; then
    echo "✓ Found expected file: bookmarks_backup.html"
    cp "$DOWNLOADS_DIR/bookmarks_backup.html" /tmp/bookmarks_export.html
    echo "bookmarks_backup.html" > /tmp/export_filename.txt
    ls -lh "$DOWNLOADS_DIR/bookmarks_backup.html"
else
    echo "Expected filename not found, searching for any recent HTML files..."
    
    # Find any HTML file in Downloads created in last 5 minutes
    RECENT_HTML=$(find "$DOWNLOADS_DIR" -name "*.html" -type f -mmin -5 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -n "$RECENT_HTML" ] && [ -f "$RECENT_HTML" ]; then
        HTML_NAME=$(basename "$RECENT_HTML")
        echo "✓ Found recent HTML file: $HTML_NAME"
        cp "$RECENT_HTML" /tmp/bookmarks_export.html
        echo "$HTML_NAME" > /tmp/export_filename.txt
        ls -lh "$RECENT_HTML"
    else
        echo "⚠ No HTML export file found in Downloads"
        echo "none" > /tmp/export_filename.txt
        
        # List all files in Downloads for debugging
        echo "Contents of Downloads folder:"
        ls -lah "$DOWNLOADS_DIR" || true
    fi
fi

# Export source bookmarks for comparison
echo "Exporting source Chrome bookmarks..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" /tmp/source_bookmarks.json
    echo "✓ Source bookmarks exported"
else
    echo "⚠ Warning: Source bookmarks not found at $CHROME_PROFILE/Bookmarks"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Bookmarks" ]; then
        cp "$ALT_PROFILE/Bookmarks" /tmp/source_bookmarks.json
        echo "✓ Source bookmarks exported from alternative location"
    fi
fi

echo "✅ Export complete"
echo "Files prepared for verification:"
echo "  - /tmp/bookmarks_export.html (exported HTML)"
echo "  - /tmp/source_bookmarks.json (source bookmarks)"
echo "  - /tmp/export_filename.txt (filename used)"