#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Folder Organization Task Export ==="

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
fi

# Gracefully close Chrome to ensure bookmarks are persisted to disk
echo "Closing Chrome to save bookmarks..."

# Send SIGTERM first for graceful shutdown
pkill -SIGTERM chrome 2>/dev/null || pkill -SIGTERM google-chrome 2>/dev/null || true
sleep 3

# Check if Chrome is still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, waiting longer..."
    sleep 2
fi

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" 2>/dev/null || pkill -9 -f "chrome" 2>/dev/null || true
    sleep 1
fi

echo "✓ Chrome closed"

# Export bookmarks file to temporary location for verification
echo "Exporting Chrome bookmarks..."

# Try primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
BOOKMARKS_FILE="$CHROME_PROFILE/Bookmarks"

if [ -f "$BOOKMARKS_FILE" ]; then
    cp "$BOOKMARKS_FILE" /tmp/bookmarks_export.json
    echo "✓ Bookmarks exported from: $BOOKMARKS_FILE"
    
    # Show file info
    ls -lh "$BOOKMARKS_FILE"
    
    # Show last modified time
    stat "$BOOKMARKS_FILE" | grep Modify || true
else
    echo "⚠ Warning: Bookmarks file not found at $BOOKMARKS_FILE"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    ALT_BOOKMARKS="$ALT_PROFILE/Bookmarks"
    
    if [ -f "$ALT_BOOKMARKS" ]; then
        cp "$ALT_BOOKMARKS" /tmp/bookmarks_export.json
        echo "✓ Bookmarks exported from alternative location: $ALT_BOOKMARKS"
    else
        echo "✗ Bookmarks file not found in any known location"
        
        # List available files for debugging
        echo "Contents of profile directories:"
        ls -la "$CHROME_PROFILE" 2>/dev/null || echo "Primary profile not found"
        ls -la "$ALT_PROFILE" 2>/dev/null || echo "Alternative profile not found"
        
        # Create empty file to prevent verification errors
        echo '{"roots":{"bookmark_bar":{"children":[]}}}' > /tmp/bookmarks_export.json
    fi
fi

# Verify bookmarks file is valid JSON
if [ -f /tmp/bookmarks_export.json ]; then
    if jq empty /tmp/bookmarks_export.json 2>/dev/null; then
        echo "✓ Bookmarks file is valid JSON"
        
        # Show bookmark bar folder count for debugging
        FOLDER_COUNT=$(jq -r '.roots.bookmark_bar.children | length' /tmp/bookmarks_export.json 2>/dev/null || echo "0")
        echo "Bookmark bar contains $FOLDER_COUNT item(s)"
    else
        echo "⚠ Warning: Bookmarks file is not valid JSON"
    fi
fi

echo "✅ Export complete"
echo "Bookmarks file ready for verification at: /tmp/bookmarks_export.json"