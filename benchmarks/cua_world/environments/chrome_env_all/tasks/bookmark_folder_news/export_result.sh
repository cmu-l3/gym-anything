#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Folder Task Export ==="

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

# Capture active tab URL via CDP for additional verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Gracefully close Chrome to ensure bookmarks are persisted to disk
echo "Closing Chrome to save bookmarks..."
# First, try graceful close
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force closing..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Wait a bit more to ensure file writes are complete
sleep 2

# Export bookmarks file to temporary location for verification
echo "Exporting Chrome bookmarks file..."

# Try primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
BOOKMARKS_EXPORTED=false

if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
    chmod 644 /tmp/bookmarks_export.json
    BOOKMARKS_EXPORTED=true
    echo "✓ Bookmarks exported from: $CHROME_PROFILE/Bookmarks"
    ls -lh "$CHROME_PROFILE/Bookmarks"
else
    echo "⚠ Bookmarks not found at: $CHROME_PROFILE/Bookmarks"
    
    # Try alternative profile location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Bookmarks" ]; then
        cp "$ALT_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        chmod 644 /tmp/bookmarks_export.json
        BOOKMARKS_EXPORTED=true
        echo "✓ Bookmarks exported from alternative location: $ALT_PROFILE/Bookmarks"
        ls -lh "$ALT_PROFILE/Bookmarks"
    else
        echo "✗ Could not find Bookmarks file in any known location"
        # Create empty JSON to prevent verification errors
        echo '{"roots":{}}' > /tmp/bookmarks_export.json
    fi
fi

if [ "$BOOKMARKS_EXPORTED" = true ]; then
    # Quick peek at bookmark structure for debugging
    echo "Bookmark bar folders:"
    python3 -c "
import json, sys
try:
    with open('/tmp/bookmarks_export.json', 'r') as f:
        data = json.load(f)
    bar = data.get('roots', {}).get('bookmark_bar', {}).get('children', [])
    folders = [c.get('name') for c in bar if c.get('type') == 'folder']
    print('  Folders found:', folders if folders else 'None')
except Exception as e:
    print('  Error reading bookmarks:', e, file=sys.stderr)
" 2>&1 || true
fi

# Also copy to a standard temp verification directory
VERIFY_DIR="/tmp/bookmark_folder_verification"
mkdir -p "$VERIFY_DIR"
if [ -f /tmp/bookmarks_export.json ]; then
    cp /tmp/bookmarks_export.json "$VERIFY_DIR/Bookmarks"
fi

echo "✅ Export complete"
echo "Verification files available at:"
echo "  - /tmp/bookmarks_export.json"
echo "  - $VERIFY_DIR/Bookmarks"