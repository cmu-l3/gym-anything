#!/bin/bash
set -e
echo "=== Setting up create_staircase_array task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/FreeCAD/staircase.FCStd
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instances
kill_freecad

# Start FreeCAD
echo "Starting FreeCAD..."
launch_freecad

# Wait for FreeCAD window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Ensure Part workbench is loaded (optional, but helpful state)
# We rely on user to select tools, but we can ensure window is ready.
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="