#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Selective History Deletion Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for context
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

# Gracefully close Chrome to ensure history is persisted to disk
echo "Closing Chrome to save history database..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export History database to temporary location for verification
echo "Exporting Chrome history database..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE/History" ]; then
    cp "$CHROME_PROFILE/History" /tmp/history_final.db
    echo "✓ History exported from primary profile to /tmp/history_final.db"
elif [ -f "$ALT_PROFILE/History" ]; then
    cp "$ALT_PROFILE/History" /tmp/history_final.db
    echo "✓ History exported from alternative profile to /tmp/history_final.db"
else
    echo "⚠ Warning: History database not found"
    echo "Searched locations:"
    echo "  - $CHROME_PROFILE/History"
    echo "  - $ALT_PROFILE/History"
fi

# Log history statistics for debugging
if [ -f "/tmp/history_final.db" ]; then
    echo "History statistics:"
    TOTAL_COUNT=$(sqlite3 /tmp/history_final.db "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "unknown")
    EXAMPLE_COUNT=$(sqlite3 /tmp/history_final.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%example%' OR title LIKE '%example%';" 2>/dev/null || echo "unknown")
    echo "  Total entries: $TOTAL_COUNT"
    echo "  Entries with 'example': $EXAMPLE_COUNT"
    
    # Sample some URLs for debugging
    echo "Sample history URLs:"
    sqlite3 /tmp/history_final.db "SELECT url FROM urls ORDER BY last_visit_time DESC LIMIT 5;" 2>/dev/null || true
fi

# Also copy baseline if it exists for comparison
if [ -f "/tmp/history_baseline.db" ]; then
    echo "✓ Baseline history database available for comparison"
fi

echo "✅ Export complete"