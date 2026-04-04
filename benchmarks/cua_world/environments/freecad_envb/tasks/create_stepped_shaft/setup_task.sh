#!/bin/bash
set -e
echo "=== Setting up create_stepped_shaft task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous output
rm -f /home/ga/Documents/FreeCAD/stepped_shaft.FCStd
rm -f /tmp/task_result.json

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD
kill_freecad

# Launch FreeCAD (empty, no file)
# Using shared utility function
launch_freecad

# Wait for FreeCAD to appear
wait_for_freecad 45

# Give it extra time to fully initialize
sleep 5

# Maximize and focus
maximize_freecad
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="