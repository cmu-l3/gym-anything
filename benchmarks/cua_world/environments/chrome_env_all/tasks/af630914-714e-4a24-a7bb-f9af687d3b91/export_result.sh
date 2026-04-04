#!/usr/bin/env bash
# set -euo pipefail

echo "=== OSWorld Chrome Task Export: af630914-714e-4a24-a7bb-f9af687d3b91 ==="

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

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
