#!/usr/bin/env bash
# set -euo pipefail

echo "=== OSWorld Chrome Task Export: 3299584d-8f11-4457-bf4c-ce98f7600250 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Export Chrome preferences for startup page verification
echo "Exporting Chrome preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    pkill chrome || true
    sleep 2
    cp "$CHROME_PROFILE/Preferences" /tmp/preferences.json
    echo "Preferences exported to /tmp/preferences.json"
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
