#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_revolution task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean up any previous artifacts to ensure clean state
rm -f /home/ga/Documents/FreeCAD/stepped_shaft.FCStd
rm -f /tmp/geometry_report.json
rm -f /tmp/task_result.json

# Kill any existing FreeCAD instance
kill_freecad
sleep 2

# Launch FreeCAD (empty, Part workbench is default from environment setup)
launch_freecad
wait_for_freecad 45

# Give FreeCAD time to fully initialize
sleep 8

# Maximize the window
maximize_freecad
sleep 2

# Dismiss any startup dialogs (Start Center is suppressed by user.cfg, but just in case)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== create_revolution task setup complete ==="