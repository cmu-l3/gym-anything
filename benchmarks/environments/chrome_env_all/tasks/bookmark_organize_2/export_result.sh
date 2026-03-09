#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Organization Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Close Chrome to ensure Bookmarks file is fully written
echo "Closing Chrome to save bookmarks..."
pkill -f "chrome.*remote-debugging-port" || true
sleep 3

# Export Bookmarks file for verification
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" /tmp/final_bookmarks.json
    echo "✓ Bookmarks exported to /tmp/final_bookmarks.json"
    
    # Also create a backup for debugging
    cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_backup.json
    
    # Pretty-print for easier debugging
    if command -v jq &> /dev/null; then
        jq '.' "$CHROME_PROFILE/Bookmarks" > /tmp/final_bookmarks_pretty.json 2>/dev/null || true
    fi
else
    echo "⚠ Warning: Bookmarks file not found at $CHROME_PROFILE/Bookmarks"
    touch /tmp/final_bookmarks.json
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    # Restart Chrome briefly for screenshot
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh chrome://bookmarks" &
    sleep 3
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
    pkill -f "chrome.*remote-debugging-port" || true
fi

echo "✅ Export complete"