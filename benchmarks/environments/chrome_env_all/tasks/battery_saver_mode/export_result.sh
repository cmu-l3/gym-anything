#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Battery Saver Mode Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification context
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

# IMPORTANT: Kill Chrome to ensure Preferences are fully written to disk
# Settings changes may be buffered in memory until Chrome closes
echo "Stopping Chrome to save preferences to disk..."
pkill -f "google-chrome" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

echo "✓ Chrome stopped, preferences should be saved"

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for verification..."

# Try primary location (CDP profile)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_battery.json
    echo "✓ Preferences exported from CDP profile: $CHROME_PROFILE"
    ls -lh "$CHROME_PROFILE/Preferences"
else
    echo "⚠ Warning: Preferences not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location (standard profile)
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_battery.json
        echo "✓ Preferences exported from standard profile: $ALT_PROFILE"
        ls -lh "$ALT_PROFILE/Preferences"
    else
        echo "✗ ERROR: Could not find Preferences file in any known location"
        echo "Searched locations:"
        echo "  - $CHROME_PROFILE/Preferences"
        echo "  - $ALT_PROFILE/Preferences"
        
        # Create marker file to indicate preferences not found
        echo "not_found" > /tmp/chrome_preferences_battery.json
    fi
fi

# Also copy to standard temp location for easier verification access
if [ -f "/tmp/chrome_preferences_battery.json" ]; then
    cp /tmp/chrome_preferences_battery.json /tmp/Preferences 2>/dev/null || true
fi

# Log file sizes for debugging
echo "Exported files:"
ls -lh /tmp/chrome_preferences_battery.json 2>/dev/null || echo "  chrome_preferences_battery.json: NOT FOUND"
ls -lh /tmp/final_screenshot.png 2>/dev/null || echo "  final_screenshot.png: NOT FOUND"

echo "✅ Export complete"
echo "Verification files ready in /tmp/"