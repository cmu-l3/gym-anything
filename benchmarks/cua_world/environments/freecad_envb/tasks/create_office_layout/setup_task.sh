#!/bin/bash
set -e
echo "=== Setting up create_office_layout task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
rm -f /home/ga/Documents/FreeCAD/office_layout.FCStd
rm -f /home/ga/Documents/FreeCAD/office_layout.dxf
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instance
kill_freecad

# Launch FreeCAD with an empty environment
echo "Launching FreeCAD..."
launch_freecad

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Ensure Draft workbench is loaded (optional, but helps speed up agent's first action)
# We won't force it, but we ensure the app is ready.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="