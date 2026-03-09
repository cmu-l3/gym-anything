#!/usr/bin/env bash
# set -euo pipefail

echo "=== OSWorld Chrome Task Export: 44ee5668-ecd5-4366-a6ce-c1c9b8d4e938 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Restart Chrome for verification (as per OSWorld postconfig)
echo "Restarting Chrome for verification..."
pkill chrome || true
sleep 2
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" || true
sleep 3

# Export Chrome browsing history
echo "Exporting Chrome history..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/History" ]; then
    # Copy History database (it's locked while Chrome is running)
    pkill chrome || true
    sleep 2
    cp "$CHROME_PROFILE/History" /tmp/history.sqlite
    echo "History exported to /tmp/history.sqlite"
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
