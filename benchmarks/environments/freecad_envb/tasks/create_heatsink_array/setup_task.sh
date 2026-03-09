#!/bin/bash
set -e
echo "=== Setting up create_heatsink_array task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_freecad
sleep 2

# Create workspace directory if it doesn't exist
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Clean up any previous attempts
rm -f /home/ga/Documents/FreeCAD/heatsink.FCStd
rm -f /tmp/geometry_report.json

# Launch FreeCAD (empty, as requested by "Starting State")
echo "Starting FreeCAD..."
launch_freecad
wait_for_freecad 30
maximize_freecad

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="