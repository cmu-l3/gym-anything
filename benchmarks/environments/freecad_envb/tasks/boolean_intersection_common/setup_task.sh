#!/bin/bash
set -e
echo "=== Setting up boolean_intersection_common task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Documents/FreeCAD/workspace_intersection.FCStd
rm -f /tmp/task_result.json

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instance
kill_freecad
sleep 2

# Launch FreeCAD with no file (clean start)
# Using generic launch function from task_utils.sh
launch_freecad
sleep 5

# Wait for FreeCAD window
wait_for_freecad 60

# Give FreeCAD time to fully initialize
sleep 5

# Maximize and focus the window
maximize_freecad
sleep 2

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="