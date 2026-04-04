#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Reading List Task Export: reading_list_articles@1 ==="

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
    su - ga -c "DISPLAY=:1 import -window root /tmp/reading_list_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/reading_list_screenshot.png"
fi

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Count tabs
    TAB_COUNT=$(jq '[.[] | select(.type == "page")] | length' /tmp/chrome_tabs.json)
    echo "Total tabs open: $TAB_COUNT"
fi

# Gracefully close Chrome to ensure Reading List is persisted to disk
echo "Closing Chrome to save Reading List..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Bookmarks file to temporary location for verification
# Reading List is stored within the Bookmarks file in Chrome
echo "Exporting Chrome Bookmarks (contains Reading List)..."

# Try multiple possible Chrome profile locations
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
    "/home/ga/.config/chromium/Default"
)

BOOKMARKS_FOUND=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
        echo "Found Bookmarks at: $CHROME_PROFILE/Bookmarks"
        cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        echo "✓ Bookmarks exported to /tmp/bookmarks_export.json"
        
        # Get file size for verification
        BOOKMARK_SIZE=$(stat -f%z "$CHROME_PROFILE/Bookmarks" 2>/dev/null || stat -c%s "$CHROME_PROFILE/Bookmarks" 2>/dev/null || echo "unknown")
        echo "Bookmarks file size: $BOOKMARK_SIZE bytes"
        
        BOOKMARKS_FOUND=true
        break
    fi
done

if [ "$BOOKMARKS_FOUND" = false ]; then
    echo "⚠ Warning: Bookmarks file not found in any known location"
    # Create empty placeholder to prevent verification errors
    echo '{"roots": {}}' > /tmp/bookmarks_export.json
fi

# Also check Preferences for any Reading List related settings
echo "Checking Chrome Preferences..."
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json 2>/dev/null || true
        echo "✓ Preferences exported"
        break
    fi
done

# Create a timestamp file to help verifier check for recent additions
date +%s > /tmp/task_completion_timestamp.txt
echo "✓ Timestamp recorded"

echo "✅ Export complete"
echo "Reading List entries should be present in Bookmarks file"