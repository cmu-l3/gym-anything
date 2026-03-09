#!/usr/bin/env bash
# set -euo pipefail

echo "=== Example Chrome Task Setup: Navigate to United Airlines Baggage Calculator ==="

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq

# Ensure Chrome is running
if ! pgrep -x "chrome" > /dev/null; then
    echo "Starting Chrome..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.united.com/en/us" || true
    sleep 5
else
    echo "Chrome is already running"
    # Navigate to starting URL
    # Click at the center of the screen
    su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key ctrl+l" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool type --delay 50 'https://www.united.com/en/us'" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

echo "=== Setup complete ==="
echo "💡 Instructions for agent:"
echo "   1. Chrome is open at https://www.united.com/en/us"
echo "   2. Navigate to the baggage fee calculator page"
echo "   3. Expected final URL should contain: 'checked-bag-fee-calculator'"
echo "   4. Use mouse and keyboard to navigate the website"

