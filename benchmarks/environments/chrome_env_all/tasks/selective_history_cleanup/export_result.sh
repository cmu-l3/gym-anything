#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Selective History Cleanup Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

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

# Capture active tab URL via CDP
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Gracefully close Chrome to ensure History is persisted to disk
echo "Closing Chrome to save history..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Export History database to temporary location for verification
echo "Exporting Chrome History database..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/History" ]; then
    cp "$CHROME_PROFILE/History" /tmp/history_export.db
    echo "✓ History database exported to /tmp/history_export.db"
    
    # Quick check of history entries
    FINAL_COUNT=$(sqlite3 /tmp/history_export.db "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "0")
    echo "  Final history entry count: $FINAL_COUNT"
    
    # Check for remaining shopping entries
    SHOPPING_REMAINING=$(sqlite3 /tmp/history_export.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%shop%' OR url LIKE '%amazon%' OR url LIKE '%ebay%' OR url LIKE '%etsy%' OR url LIKE '%walmart%';" 2>/dev/null || echo "unknown")
    echo "  Shopping entries remaining: $SHOPPING_REMAINING"
else
    echo "⚠ Warning: History database not found at $CHROME_PROFILE/History"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/History" ]; then
        cp "$ALT_PROFILE/History" /tmp/history_export.db
        echo "✓ History exported from alternative location"
    else
        echo "✗ Could not find History database"
    fi
fi

# Also copy initial counts for verification comparison
if [ -f /tmp/initial_history_total.txt ]; then
    cp /tmp/initial_history_total.txt /tmp/initial_counts_export.txt
    echo "✓ Initial counts exported for comparison"
fi

echo "✅ Export complete"