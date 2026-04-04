#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Download Location Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure settings are synced
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

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save download location setting..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_download.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_download.json"
    
    # Extract and display download directory for debugging
    DL_DIR=$(grep -o '"default_directory":"[^"]*"' "$CHROME_PROFILE/Preferences" | cut -d'"' -f4 || echo "not_found")
    echo "Download directory in Preferences: $DL_DIR"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_download.json
        echo "✓ Preferences exported from alternative location"
        
        DL_DIR=$(grep -o '"default_directory":"[^"]*"' "$ALT_PROFILE/Preferences" | cut -d'"' -f4 || echo "not_found")
        echo "Download directory in Preferences: $DL_DIR"
    else
        echo "✗ Could not find Preferences file in any known location"
    fi
fi

# List contents of home directory to help verify directory creation
echo "Contents of /home/ga directory:"
ls -la /home/ga/ 2>/dev/null | grep -E '^d' | tail -10 || true

echo "✅ Export complete"