#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmarklet Creation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification context
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
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export bookmarks file to /tmp for verification
echo "Exporting Chrome Bookmarks file..."

# Try primary Chrome profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
    echo "✓ Bookmarks exported from: $CHROME_PROFILE/Bookmarks"
    ls -lh "$CHROME_PROFILE/Bookmarks"
else
    echo "⚠ Bookmarks not found at $CHROME_PROFILE/Bookmarks"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Bookmarks" ]; then
        cp "$ALT_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        echo "✓ Bookmarks exported from alternative location: $ALT_PROFILE/Bookmarks"
        ls -lh "$ALT_PROFILE/Bookmarks"
    else
        echo "✗ Could not find Bookmarks file in any known location"
        # Create empty file to prevent verification errors
        echo '{"roots": {"bookmark_bar": {"children": []}}}' > /tmp/bookmarks_export.json
    fi
fi

# Verify bookmarks file was exported successfully
if [ -f /tmp/bookmarks_export.json ]; then
    FILE_SIZE=$(stat -f%z /tmp/bookmarks_export.json 2>/dev/null || stat -c%s /tmp/bookmarks_export.json 2>/dev/null || echo "0")
    echo "Bookmarks file size: $FILE_SIZE bytes"
    
    if [ "$FILE_SIZE" -gt 100 ]; then
        echo "✓ Bookmarks file appears valid"
    else
        echo "⚠ Bookmarks file seems too small"
    fi
else
    echo "✗ Bookmarks export failed"
fi

echo "✅ Export complete"
echo "Verification files available in /tmp/"