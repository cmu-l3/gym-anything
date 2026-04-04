#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Memory Saver Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure settings are synced
echo "Focusing Chrome window..."
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
    
    # Check if agent is still on settings page
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent is on Chrome settings page"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are persisted to disk
echo "Closing Chrome to save Memory Saver configuration..."
pkill -f "google-chrome" || pkill -f "chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || pkill -9 -f "chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

EXPORTED=false

# Try primary profile location
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_final.json
    echo "✓ Preferences exported from primary profile"
    EXPORTED=true
    
    # Show file size for verification
    ls -lh "$CHROME_PROFILE/Preferences"
fi

# Try alternative profile location if primary failed
if [ "$EXPORTED" = false ] && [ -f "$ALT_PROFILE/Preferences" ]; then
    cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_final.json
    echo "✓ Preferences exported from alternative profile"
    EXPORTED=true
    
    ls -lh "$ALT_PROFILE/Preferences"
fi

if [ "$EXPORTED" = false ]; then
    echo "⚠ Warning: Could not find Preferences file in any known location"
    # Create empty JSON to prevent verifier errors
    echo "{}" > /tmp/chrome_preferences_final.json
fi

# Compare with backup if available
if [ -f "$CHROME_PROFILE/Preferences.backup_pre_task" ]; then
    echo "Checking for changes in Preferences file..."
    if diff "$CHROME_PROFILE/Preferences.backup_pre_task" "$CHROME_PROFILE/Preferences" > /dev/null 2>&1; then
        echo "⚠ Warning: Preferences file appears unchanged"
    else
        echo "✓ Preferences file has been modified"
    fi
elif [ -f "$ALT_PROFILE/Preferences.backup_pre_task" ]; then
    if diff "$ALT_PROFILE/Preferences.backup_pre_task" "$ALT_PROFILE/Preferences" > /dev/null 2>&1; then
        echo "⚠ Warning: Preferences file appears unchanged"
    else
        echo "✓ Preferences file has been modified"
    fi
fi

echo "✅ Export complete"
echo "Verification files ready at /tmp/chrome_preferences_final.json"