#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Download History Search Task Export: download_history_search@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window to ensure final state
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_active_url.txt
    
    # Check if agent reached downloads page
    if echo "$ACTIVE_URL" | grep -qi "chrome://downloads"; then
        echo "✓ Agent reached chrome://downloads/ page"
    else
        echo "⚠ Active tab is not on downloads page: $ACTIVE_URL"
    fi
else
    echo "⚠ Warning: Could not capture CDP information"
    echo "unknown" > /tmp/final_active_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Close Chrome gracefully to ensure History database is properly closed
echo "Closing Chrome to finalize History database..."
pkill -f "google-chrome" || pkill -f "chromium" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || pkill -9 -f "chromium" || true
    sleep 1
fi

# Export Chrome History database for verification
echo "Exporting Chrome History database..."
CHROME_PROFILE_PRIMARY="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE_ALT="/home/ga/.config/google-chrome/Default"

HISTORY_EXPORTED=false

if [ -f "$CHROME_PROFILE_PRIMARY/History" ]; then
    echo "Copying History from primary profile..."
    cp "$CHROME_PROFILE_PRIMARY/History" /tmp/chrome_history.db
    HISTORY_EXPORTED=true
    echo "✓ History database exported from: $CHROME_PROFILE_PRIMARY"
elif [ -f "$CHROME_PROFILE_ALT/History" ]; then
    echo "Copying History from alternative profile..."
    cp "$CHROME_PROFILE_ALT/History" /tmp/chrome_history.db
    HISTORY_EXPORTED=true
    echo "✓ History database exported from: $CHROME_PROFILE_ALT"
else
    echo "⚠ Warning: History database not found in either profile location"
    # Create empty database to prevent verification errors
    touch /tmp/chrome_history.db
fi

# Query download history for debugging
if [ "$HISTORY_EXPORTED" = true ] && command -v sqlite3 &> /dev/null; then
    echo ""
    echo "Download history entries (for debugging):"
    sqlite3 /tmp/chrome_history.db "SELECT target_path, start_time FROM downloads ORDER BY start_time DESC LIMIT 10;" 2>/dev/null || echo "Could not query downloads table"
fi

# Export list of downloaded files
echo ""
echo "Files in Downloads folder:"
ls -lh /home/ga/Downloads/ > /tmp/downloads_folder_list.txt 2>/dev/null || echo "none" > /tmp/downloads_folder_list.txt
cat /tmp/downloads_folder_list.txt

# Create verification summary
cat > /tmp/verification_summary.txt << EOF
Download History Search Task - Export Summary
==============================================
Active URL: $(cat /tmp/final_active_url.txt 2>/dev/null || echo "unknown")
History DB Exported: $HISTORY_EXPORTED
Downloads Folder: /home/ga/Downloads
Timestamp: $(date)
EOF

echo ""
cat /tmp/verification_summary.txt

echo "✅ Export complete"