#!/bin/bash
set -euo pipefail

echo "=== Setting up measure_distance task ==="

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
echo "Task: Measure the distance from the Statue of Liberty to the Empire State Building"
echo "Steps:"
echo "1. Navigate to New York City area"
echo "2. Open the Ruler tool (Tools > Ruler or Ctrl+Alt+R)"
echo "3. Click on the Statue of Liberty to set the first point"
echo "4. Click on the Empire State Building to set the second point"
echo "5. Note the distance shown (approximately 8.5 km or 5.3 miles)"
