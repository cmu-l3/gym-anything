#!/bin/bash
set -euo pipefail

echo "=== Setting up search_coordinates task ==="

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
nohup sudo -u ga google-earth-pro > /home/ga/google_earth.log 2>&1 &
sleep 5

# Wait for window to appear
for i in {1..30}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected"
        break
    fi
    sleep 1
done

# Full screen the window
wmctrl -r "Google Earth" -b add,fullscreen

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Task: Navigate to GPS coordinates 40.7128, -74.0060 (New York City)"
echo "Use the search bar to enter the coordinates in format: 40.7128, -74.0060"
