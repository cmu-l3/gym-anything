#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmarks Folder Organization Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure bookmarks are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
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

# Export bookmarks file to temporary location for verification
echo "Exporting Chrome bookmarks..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
    echo "✓ Bookmarks exported to /tmp/bookmarks_export.json"
    
    # Show summary of bookmarks structure
    echo "Bookmarks structure summary:"
    jq -r '.roots.bookmark_bar.children[] | "\(.type): \(.name)"' "$CHROME_PROFILE/Bookmarks" 2>/dev/null || true
else
    echo "⚠ Warning: Bookmarks file not found at $CHROME_PROFILE/Bookmarks"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Bookmarks" ]; then
        cp "$ALT_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        echo "✓ Bookmarks exported from alternative location"
    else
        echo "✗ Could not find Bookmarks file in any known location"
        touch /tmp/bookmarks_export.json
    fi
fi

echo "✅ Export complete"