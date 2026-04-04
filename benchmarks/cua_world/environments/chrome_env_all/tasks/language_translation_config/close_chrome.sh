#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Language Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure preferences are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for debugging
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are persisted to disk
echo "Closing Chrome to save language preferences..."
pkill -TERM chrome || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_export.json"
    
    # Show file size for debugging
    ls -lh "$CHROME_PROFILE/Preferences" || true
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE"
    else
        echo "✗ Could not find Preferences file in any known location"
        
        # List directories for debugging
        echo "Listing Chrome config directories:"
        ls -la /home/ga/.config/ | grep -i chrome || true
    fi
fi

# Also backup to a secondary location for verifier fallback
if [ -f "/tmp/chrome_preferences_export.json" ]; then
    cp /tmp/chrome_preferences_export.json /tmp/language_prefs_backup.json || true
fi

echo "✅ Export complete"
echo "Preferences should now contain Spanish language configuration"