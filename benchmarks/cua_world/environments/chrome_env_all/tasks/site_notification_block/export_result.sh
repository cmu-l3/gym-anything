#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Notification Blocking Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture current URL via CDP for verification context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if agent is in settings (good indicator they attempted the task)
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent navigated to Chrome settings"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Final screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save notification settings..."

# First, try graceful close
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Wait for file system sync
sync
sleep 1

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_final.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_final.json"
    
    # Show file size for debugging
    ls -lh "$CHROME_PROFILE/Preferences" || true
    
    # Quick check if notification exceptions exist
    if grep -q '"notifications"' "$CHROME_PROFILE/Preferences" 2>/dev/null; then
        echo "✓ Notification exceptions section found in Preferences"
    else
        echo "⚠ Warning: No notification exceptions section found"
    fi
    
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_final.json
        echo "✓ Preferences exported from alternative location"
    else
        echo "✗ Could not find Preferences file in any known location"
        touch /tmp/chrome_preferences_final.json
    fi
fi

# Also copy backup if it exists (for comparison)
if [ -f "$CHROME_PROFILE/Preferences.backup" ]; then
    cp "$CHROME_PROFILE/Preferences.backup" /tmp/chrome_preferences_backup.json
    echo "✓ Backup preferences also exported for comparison"
fi

echo "✅ Export complete"
echo "Preferences files ready for verification"