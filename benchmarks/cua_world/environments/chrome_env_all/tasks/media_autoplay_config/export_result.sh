#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Media Autoplay Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if user was on settings page
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ User was on Chrome settings page"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."

# Try primary location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    
    # Show sound exceptions for debugging
    SOUND_EXCEPTIONS=$(jq -r '.profile.content_settings.exceptions.sound // {}' /tmp/chrome_preferences_export.json 2>/dev/null)
    if [ "$SOUND_EXCEPTIONS" != "{}" ]; then
        echo "Sound exceptions found:"
        echo "$SOUND_EXCEPTIONS" | jq -r 'keys[]' || echo "(could not parse keys)"
    else
        echo "⚠ No sound exceptions found in Preferences"
    fi
else
    echo "⚠ Preferences not found at primary location, trying alternatives..."
    
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported from alternative location: $CHROME_PROFILE/Preferences"
    else
        echo "✗ Error: Could not find Preferences file at any known location"
        echo "Searched locations:"
        echo "  - /home/ga/.config/google-chrome-cdp/Default/Preferences"
        echo "  - /home/ga/.config/google-chrome/Default/Preferences"
        
        # Create empty file to prevent verification errors
        echo "{}" > /tmp/chrome_preferences_export.json
    fi
fi

# Also backup to standard location for verifier access
if [ -f /tmp/chrome_preferences_export.json ]; then
    cp /tmp/chrome_preferences_export.json /tmp/chrome_prefs_backup.json || true
fi

echo "✅ Export complete"
echo "Preferences file ready for verification at: /tmp/chrome_preferences_export.json"