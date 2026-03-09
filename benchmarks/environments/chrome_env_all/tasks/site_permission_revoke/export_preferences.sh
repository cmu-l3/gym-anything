#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site Permission Management Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for context
echo "Capturing final state via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if user was in settings (good sign they attempted the task)
    if echo "$ACTIVE_URL" | grep -q "chrome://settings"; then
        echo "✓ User was in Chrome settings"
    fi
fi

# Take a screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are written to disk
echo "Closing Chrome to persist preference changes..."
pkill -TERM chrome || true
sleep 3

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 chrome || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."

# Try primary location (CDP profile)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
PREFS_FILE="$CHROME_PROFILE/Preferences"

if [ -f "$PREFS_FILE" ]; then
    cp "$PREFS_FILE" /tmp/preferences_after_task.json
    echo "✓ Preferences exported from CDP profile to /tmp/preferences_after_task.json"
    ls -lh /tmp/preferences_after_task.json
else
    echo "⚠ Preferences not found in CDP profile, trying standard location..."
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    PREFS_FILE="$CHROME_PROFILE/Preferences"
    
    if [ -f "$PREFS_FILE" ]; then
        cp "$PREFS_FILE" /tmp/preferences_after_task.json
        echo "✓ Preferences exported from standard profile to /tmp/preferences_after_task.json"
        ls -lh /tmp/preferences_after_task.json
    else
        echo "✗ Error: Could not find Preferences file in any known location"
        echo "Searched locations:"
        echo "  - /home/ga/.config/google-chrome-cdp/Default/Preferences"
        echo "  - /home/ga/.config/google-chrome/Default/Preferences"
    fi
fi

# Also copy the "before" state if it exists
if [ -f "/tmp/preferences_before_task.json" ]; then
    echo "✓ Before-state preferences available for comparison"
    ls -lh /tmp/preferences_before_task.json
else
    echo "⚠ Warning: Before-state preferences not found"
fi

echo "✅ Export complete"
echo "Verification will compare before/after Preferences to detect permission changes"