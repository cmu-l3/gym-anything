#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Autofill Address Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
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
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot_autofill.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot_autofill.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save autofill data..."
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
if [ ! -d "$CHROME_PROFILE" ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_autofill.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_autofill.json"
    
    # Show file size for debugging
    ls -lh "$CHROME_PROFILE/Preferences"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # List available profile directories for debugging
    echo "Available Chrome profiles:"
    ls -la /home/ga/.config/ | grep chrome || true
fi

# Also copy to standard temp location as backup
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/Preferences || true
fi

echo "✅ Export complete"
echo "Autofill data should now be saved in Chrome Preferences"