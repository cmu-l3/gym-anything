#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Payment Method Autofill Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time to ensure data is synced
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

# Gracefully close Chrome to ensure Web Data database is properly written to disk
echo "Closing Chrome to save payment method data..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Export Web Data database to temporary location for verification
echo "Exporting Chrome Web Data database..."

# Try primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Web Data" ]; then
    cp "$CHROME_PROFILE/Web Data" /tmp/web_data_export.db
    echo "✓ Web Data exported from: $CHROME_PROFILE/Web Data"
    
    # Check if credit_cards table has entries
    CARD_COUNT=$(sqlite3 /tmp/web_data_export.db "SELECT COUNT(*) FROM credit_cards;" 2>/dev/null || echo "0")
    echo "  Credit cards in database: $CARD_COUNT"
else
    # Try alternative profile location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Web Data" ]; then
        cp "$ALT_PROFILE/Web Data" /tmp/web_data_export.db
        echo "✓ Web Data exported from: $ALT_PROFILE/Web Data"
        
        CARD_COUNT=$(sqlite3 /tmp/web_data_export.db "SELECT COUNT(*) FROM credit_cards;" 2>/dev/null || echo "0")
        echo "  Credit cards in database: $CARD_COUNT"
    else
        echo "⚠ Warning: Web Data file not found in any known location"
        # Create an empty marker file
        touch /tmp/web_data_export.db
    fi
fi

# Copy task start timestamp for verification
if [ -f /tmp/task_start_timestamp.txt ]; then
    cp /tmp/task_start_timestamp.txt /tmp/task_timestamp.txt
fi

echo "✅ Export complete"
echo "Verification files prepared in /tmp/"