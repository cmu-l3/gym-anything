#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Autofill Address Update Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure changes are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for debugging
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
else
    echo "⚠ Warning: Could not capture CDP information"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot_autofill.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot_autofill.png"
fi

# CRITICAL: Close Chrome gracefully to ensure Web Data is flushed to disk
echo "Closing Chrome to save autofill changes..."
pkill -TERM -f "google-chrome" || true
sleep 3

# Verify Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Give extra time for database to be fully written
sleep 1

# Determine which Chrome profile was used
CHROME_PROFILE_CDP="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE_STD="/home/ga/.config/google-chrome/Default"

CHROME_PROFILE=""
if [ -f "$CHROME_PROFILE_CDP/Web Data" ]; then
    CHROME_PROFILE="$CHROME_PROFILE_CDP"
    echo "Found Web Data at: $CHROME_PROFILE_CDP"
elif [ -f "$CHROME_PROFILE_STD/Web Data" ]; then
    CHROME_PROFILE="$CHROME_PROFILE_STD"
    echo "Found Web Data at: $CHROME_PROFILE_STD"
else
    echo "⚠ Warning: Web Data file not found in either profile location"
fi

# Copy Web Data to temp location for verification
if [ -n "$CHROME_PROFILE" ] && [ -f "$CHROME_PROFILE/Web Data" ]; then
    echo "Exporting Web Data database for verification..."
    cp "$CHROME_PROFILE/Web Data" /tmp/web_data_export.db
    echo "✓ Web Data exported to /tmp/web_data_export.db"
    
    # Also copy to standard name for verifier
    cp "$CHROME_PROFILE/Web Data" /tmp/WebData
    
    # Show size for debugging
    ls -lh "$CHROME_PROFILE/Web Data"
    
    # Quick sanity check: show address count
    if command -v sqlite3 &> /dev/null; then
        ADDR_COUNT=$(sqlite3 "$CHROME_PROFILE/Web Data" "SELECT COUNT(*) FROM autofill_profile_addresses;" 2>/dev/null || echo "unknown")
        echo "  Total addresses in database: $ADDR_COUNT"
    fi
else
    echo "⚠ Could not find Web Data database to export"
fi

echo "✅ Export complete"