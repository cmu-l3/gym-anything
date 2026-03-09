#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Search and Bulk Move Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
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
    
    # Check if Bookmark Manager was opened
    if echo "$ACTIVE_URL" | grep -q "chrome://bookmarks"; then
        echo "✓ Bookmark Manager is currently open"
    fi
fi

# Gracefully close Chrome to ensure bookmarks are persisted to disk
echo "Closing Chrome to save bookmarks..."
pkill -TERM -f "google-chrome" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export bookmarks file to temporary location for verification
echo "Exporting Chrome bookmarks..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_final.json
    echo "✓ Bookmarks exported to /tmp/bookmarks_final.json"
    
    # Show basic info about bookmarks structure
    if command -v jq &> /dev/null; then
        FOLDER_COUNT=$(jq '[.roots.bookmark_bar.children[] | select(.type == "folder")] | length' /tmp/bookmarks_final.json 2>/dev/null || echo "unknown")
        BOOKMARK_COUNT=$(jq '[.roots.bookmark_bar.children[] | select(.type == "url")] | length' /tmp/bookmarks_final.json 2>/dev/null || echo "unknown")
        echo "  Folders in bookmark bar: $FOLDER_COUNT"
        echo "  Bookmarks in bookmark bar: $BOOKMARK_COUNT"
        
        # Check if Tech News folder exists
        TECH_NEWS_EXISTS=$(jq '[.roots.bookmark_bar.children[] | select(.type == "folder" and .name == "Tech News")] | length' /tmp/bookmarks_final.json 2>/dev/null || echo "0")
        if [ "$TECH_NEWS_EXISTS" -gt 0 ]; then
            echo "  ✓ 'Tech News' folder detected"
            TECH_NEWS_ITEMS=$(jq '[.roots.bookmark_bar.children[] | select(.type == "folder" and .name == "Tech News") | .children[]] | length' /tmp/bookmarks_final.json 2>/dev/null || echo "0")
            echo "  ✓ 'Tech News' folder contains $TECH_NEWS_ITEMS items"
        else
            echo "  ⚠ 'Tech News' folder not found"
        fi
    fi
else
    echo "⚠ Warning: Bookmarks file not found at $CHROME_PROFILE/Bookmarks"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Bookmarks" ]; then
        cp "$ALT_PROFILE/Bookmarks" /tmp/bookmarks_final.json
        echo "✓ Bookmarks exported from alternative location"
    else
        echo "✗ Could not find Bookmarks file in any known location"
        # Create empty structure to prevent verification errors
        echo '{"roots":{"bookmark_bar":{"children":[]}}}' > /tmp/bookmarks_final.json
    fi
fi

# Also backup initial bookmarks for comparison if needed
if [ -f "$CHROME_PROFILE/Bookmarks.bak" ]; then
    cp "$CHROME_PROFILE/Bookmarks.bak" /tmp/bookmarks_initial.json 2>/dev/null || true
fi

echo "✅ Export complete"
echo "Bookmarks file ready for verification"