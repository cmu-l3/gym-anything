#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark All Tabs Task Export: bookmark_all_tabs@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure bookmarks are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture all tabs via CDP for verification context
echo "Capturing all tabs information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs.json > /tmp/chrome_page_tabs.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs for easy inspection
    jq -r '.[] | .url' /tmp/chrome_page_tabs.json > /tmp/tab_urls.txt
    
    echo "Current open tabs:"
    cat /tmp/tab_urls.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs.json
    touch /tmp/tab_urls.txt
fi

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
    
    # Show a preview of bookmark bar folders for debugging
    if command -v jq &> /dev/null; then
        echo "Bookmark bar folders:"
        jq -r '.roots.bookmark_bar.children[]? | select(.type == "folder") | .name' /tmp/bookmarks_export.json 2>/dev/null || echo "  (none or error parsing)"
    fi
else
    echo "⚠ Warning: Bookmarks file not found at $CHROME_PROFILE/Bookmarks"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Bookmarks" ]; then
        cp "$ALT_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        echo "✓ Bookmarks exported from alternative location: $ALT_PROFILE"
    else
        echo "✗ Could not find Bookmarks file in any known location"
        # Create empty bookmarks structure to prevent verification errors
        echo '{"roots":{"bookmark_bar":{"children":[]}}}' > /tmp/bookmarks_export.json
    fi
fi

echo "✅ Export complete"