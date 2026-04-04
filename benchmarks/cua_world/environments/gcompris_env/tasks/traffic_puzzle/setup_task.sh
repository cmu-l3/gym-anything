#!/bin/bash
set -e
echo "=== Setting up Traffic Puzzle task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any pre-existing artifacts
rm -f /tmp/traffic_completed.png
rm -f /tmp/task_result.json

# Kill any existing GCompris instances
kill_gcompris

# Launch GCompris at main menu
# The launch_gcompris utility handles backgrounding and waiting for the window
launch_gcompris

# Maximize the window for full visibility
maximize_gcompris

# Dismiss any potential startup dialogs (esc key)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot for evidence (End of setup)
take_screenshot /tmp/task_initial.png

echo "=== Traffic Puzzle task setup complete ==="
echo "Task: Navigate to Traffic activity and solve Level 1."