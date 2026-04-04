#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up spreadsheet parametric task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous artifacts
rm -f /home/ga/Documents/FreeCAD/parametric_bracket.FCStd
rm -f /tmp/task_result.json

# Ensure workspace exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD
kill_freecad

# Launch FreeCAD with blank session
echo "Launching FreeCAD..."
launch_freecad

# Wait for FreeCAD window
wait_for_freecad 45

# Give it time to fully initialize
sleep 8

# Maximize
maximize_freecad
sleep 2

# Dismiss any startup dialogs (Start Center is suppressed by user.cfg, but just in case)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="