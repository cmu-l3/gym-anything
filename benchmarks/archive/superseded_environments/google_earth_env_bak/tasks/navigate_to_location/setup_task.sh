#!/bin/bash
set -euo pipefail

echo "=== Setting up navigate_to_location task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 1

# Start Google Earth Pro
# Important to use nohup to avoid the script being killed by the shell
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_initial.log 2>&1 &
sleep 5

# Wait for window to appear
for i in {1..30}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected"
        break
    fi
    sleep 1
done

echo "Window ID: $(wmctrl -l | grep -i 'Google Earth' | awk '{print $1}')"

# Full screen the window
wmctrl -r "Google Earth" -b add,fullscreen

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true


echo "=== Task setup complete ==="
echo "Task: Navigate to the Eiffel Tower in Paris, France"
echo "Use the search bar (Ctrl+F or click search) to search for 'Eiffel Tower, Paris'"

