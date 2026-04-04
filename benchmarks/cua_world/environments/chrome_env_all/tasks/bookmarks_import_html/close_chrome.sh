#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmarks Import Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure bookmarks are synced
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
else
    echo "⚠ CDP not accessible"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure bookmarks are persisted to disk
echo "Closing Chrome to save bookmarks..."
pkill -TERM -f "google-chrome" || pkill -TERM -f "chromium" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || pkill -9 -f "chromium" || true
    sleep 1
fi

echo "Chrome closed successfully"

# Export bookmarks file to temporary location for verification
echo "Exporting Chrome bookmarks for verification..."
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

BOOKMARKS_EXPORTED=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
        cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        echo "✓ Bookmarks exported from: $CHROME_PROFILE/Bookmarks"
        BOOKMARKS_EXPORTED=true
        
        # Also show a preview of the bookmarks structure
        if command -v jq &> /dev/null; then
            echo "Bookmarks preview:"
            jq '.roots.bookmark_bar.children[] | select(.type == "folder") | .name' /tmp/bookmarks_export.json 2>/dev/null || echo "Could not preview bookmarks"
        fi
        break
    fi
done

if [ "$BOOKMARKS_EXPORTED" = false ]; then
    echo "⚠ Warning: Bookmarks file not found in any known location"
    # Create empty file to prevent verification errors
    echo '{"roots":{"bookmark_bar":{"children":[]}}}' > /tmp/bookmarks_export.json
fi

# Also copy the original HTML file for reference
if [ -f "/home/ga/Downloads/bookmarks_to_import.html" ]; then
    cp "/home/ga/Downloads/bookmarks_to_import.html" /tmp/bookmarks_source.html
    echo "✓ Source HTML copied for reference"
fi

echo "✅ Export complete"