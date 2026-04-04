#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up parametric_plate task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean any previous output to ensure a fresh start
rm -f /home/ga/Documents/FreeCAD/parametric_plate.FCStd
rm -f /tmp/task_result.json

# Ensure workspace exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instance
kill_freecad

# Launch FreeCAD with an empty document
# We don't load a file, but we ensure the app is open
launch_freecad
wait_for_freecad 60

# Maximize the window
maximize_freecad

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== parametric_plate task setup complete ==="