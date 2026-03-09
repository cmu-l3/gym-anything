#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Multi-Tab Bookmark Snapshot Task Export: bookmark_tabs_session@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture all tabs via CDP before closing
echo "Capturing all tabs information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs_final.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs_final.json > /tmp/chrome_page_tabs_final.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs_final.json)
    echo "✓ Found $TAB_COUNT page tab(s) at time of export"
    
    # Extract URLs for debugging
    jq -r '.[] | .url' /tmp/chrome_page_tabs_final.json > /tmp/tab_urls_final.txt
    echo "Tab URLs:"
    cat /tmp/tab_urls_final.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "[]" > /tmp/chrome_page_tabs_final.json
    touch /tmp/tab_urls_final.txt
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

# Export bookmarks file to temporary location for verification
echo "Exporting Chrome bookmarks..."

# Try multiple possible Chrome profile locations
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

BOOKMARKS_EXPORTED=false

for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
        cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        echo "✓ Bookmarks exported from: $CHROME_PROFILE/Bookmarks"
        ls -lh "$CHROME_PROFILE/Bookmarks"
        BOOKMARKS_EXPORTED=true
        break
    fi
done

if [ "$BOOKMARKS_EXPORTED" = false ]; then
    echo "⚠ Warning: Bookmarks file not found in any expected location"
    echo "Checked locations:"
    for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
        echo "  - $CHROME_PROFILE/Bookmarks"
    done
    
    # Create empty file to prevent verification errors
    echo "{}" > /tmp/bookmarks_export.json
fi

echo "✅ Export complete"
echo "Verification files ready:"
echo "  - /tmp/bookmarks_export.json"
echo "  - /tmp/chrome_page_tabs_final.json"
echo "  - /tmp/final_screenshot.png"