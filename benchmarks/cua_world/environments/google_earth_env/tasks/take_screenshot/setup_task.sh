#!/bin/bash
set -euo pipefail

echo "=== Setting up take_screenshot task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 1

# Clean up any pre-existing screenshots on Desktop for clean test
rm -f /home/ga/Desktop/*.jpg /home/ga/Desktop/*.jpeg /home/ga/Desktop/*.png 2>/dev/null || true

# Ensure Desktop directory exists
sudo -u ga mkdir -p /home/ga/Desktop
sudo -u ga mkdir -p /home/ga/Pictures

# Start Google Earth Pro
# Important to use nohup to avoid the script being killed by the shell
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth.log 2>&1 &
sleep 5

# Wait for window to appear
for i in {1..30}; do
    if wmctrl -l | grep -i "Google Earth"; then
        echo "Google Earth window detected"
        break
    fi
    sleep 1
done

# print the window id
echo "Window ID: $(wmctrl -l | grep -i 'Google Earth' | awk '{print $1}')"

# Focus the Google Earth window
# Full screen the window
wmctrl -r "Google Earth" -b add,fullscreen

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true


echo "=== Task setup complete ==="
echo "Task: Navigate to Mount Everest and save a screenshot"
echo "Steps:"
echo "1. Search for 'Mount Everest' in the search bar"
echo "2. Wait for the view to load"
echo "3. Use File > Save > Save Image... OR Edit > Copy Image"
echo "4. Save the image to the Desktop folder"
echo "Keyboard shortcut: Ctrl+Alt+S may also work for saving images"
