#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome History Bulk Bookmark Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
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
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure History and Bookmarks are persisted to disk
echo "Closing Chrome to save History and Bookmarks..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export History database to temporary location for verification
echo "Exporting Chrome History database..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/History" ]; then
    cp "$CHROME_PROFILE/History" /tmp/history_export.db
    echo "✓ History exported to /tmp/history_export.db"
    
    # Display sample of Python-related history entries
    echo "Sample Python-related history entries:"
    sqlite3 /tmp/history_export.db "SELECT url FROM urls WHERE url LIKE '%python%' LIMIT 5;" 2>/dev/null || true
else
    echo "⚠ Warning: History file not found at $CHROME_PROFILE/History"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/History" ]; then
        cp "$ALT_PROFILE/History" /tmp/history_export.db
        echo "✓ History exported from alternative location"
    fi
fi

# Export Bookmarks file to temporary location for verification
echo "Exporting Chrome Bookmarks..."
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
    echo "✓ Bookmarks exported to /tmp/bookmarks_export.json"
    
    # Check if Python Resources folder exists
    if grep -q "Python Resources" /tmp/bookmarks_export.json 2>/dev/null; then
        echo "✓ 'Python Resources' folder detected in bookmarks"
    else
        echo "⚠ 'Python Resources' folder not found in bookmarks"
    fi
else
    echo "⚠ Warning: Bookmarks file not found at $CHROME_PROFILE/Bookmarks"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Bookmarks" ]; then
        cp "$ALT_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        echo "✓ Bookmarks exported from alternative location"
    fi
fi

echo "✅ Export complete"
echo "Files available for verification:"
echo "  - /tmp/history_export.db (Chrome History)"
echo "  - /tmp/bookmarks_export.json (Chrome Bookmarks)"