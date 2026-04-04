#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Zoom Configuration Task Export: zoom_config@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Give Chrome a moment to save any pending preference changes
echo "Allowing Chrome to save preferences..."
sleep 2

# Gracefully close Chrome to ensure preferences are written to disk
echo "Closing Chrome to persist settings..."
pkill -f chrome || true
sleep 3

# Verify Chrome has fully closed
if pgrep -f chrome > /dev/null; then
    echo "⚠ Chrome still running, forcing termination..."
    pkill -9 -f chrome || true
    sleep 2
fi

# Export Chrome preferences for verification
echo "Exporting Chrome Preferences file..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported to /tmp/chrome_preferences.json"
    
    # Log file size for debugging
    ls -lh /tmp/chrome_preferences.json
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternate location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from alternate location: $ALT_PROFILE/Preferences"
    fi
fi

# Take a final screenshot (optional, for debugging)
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/zoom_config_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/zoom_config_screenshot.png"
fi

echo "✅ Export complete"