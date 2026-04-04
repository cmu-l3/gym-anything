#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Import Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional verification
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

# Gracefully close Chrome to ensure bookmarks are persisted to disk
echo "Closing Chrome to save bookmarks..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

echo "Chrome closed, waiting for file sync..."
sleep 1

# Export bookmarks file to temporary location for verification
echo "Exporting Chrome bookmarks for verification..."

# Try multiple possible Chrome profile locations
BOOKMARKS_FOUND=false

# Primary location (with CDP suffix)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    echo "✓ Found bookmarks at: $CHROME_PROFILE/Bookmarks"
    cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
    ls -lh "$CHROME_PROFILE/Bookmarks"
    BOOKMARKS_FOUND=true
fi

# Alternative location (standard Chrome profile)
if [ "$BOOKMARKS_FOUND" = false ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
        echo "✓ Found bookmarks at: $CHROME_PROFILE/Bookmarks"
        cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        ls -lh "$CHROME_PROFILE/Bookmarks"
        BOOKMARKS_FOUND=true
    fi
fi

# Third location (Chromium)
if [ "$BOOKMARKS_FOUND" = false ]; then
    CHROME_PROFILE="/home/ga/.config/chromium/Default"
    if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
        echo "✓ Found bookmarks at: $CHROME_PROFILE/Bookmarks"
        cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        ls -lh "$CHROME_PROFILE/Bookmarks"
        BOOKMARKS_FOUND=true
    fi
fi

if [ "$BOOKMARKS_FOUND" = false ]; then
    echo "⚠ Warning: Bookmarks file not found in any standard location"
    # Create empty JSON to prevent verifier errors
    echo '{"roots": {"bookmark_bar": {"children": []}}}' > /tmp/bookmarks_export.json
else
    echo "✓ Bookmarks exported to /tmp/bookmarks_export.json"
    # Show file size for debugging
    FILE_SIZE=$(stat -f%z /tmp/bookmarks_export.json 2>/dev/null || stat -c%s /tmp/bookmarks_export.json 2>/dev/null || echo "unknown")
    echo "Bookmarks file size: $FILE_SIZE bytes"
fi

# Also verify the source HTML file still exists
if [ -f "/home/ga/Downloads/bookmarks_import.html" ]; then
    echo "✓ Source HTML file confirmed in Downloads"
    cp "/home/ga/Downloads/bookmarks_import.html" /tmp/bookmarks_source.html
else
    echo "⚠ Source HTML file not found (may have been moved during import)"
fi

echo "✅ Export complete"
echo "Files prepared for verification:"
echo "  - /tmp/bookmarks_export.json (Chrome bookmarks)"
echo "  - /tmp/final_url.txt (last active URL)"
echo "  - /tmp/final_screenshot.png (screenshot)"