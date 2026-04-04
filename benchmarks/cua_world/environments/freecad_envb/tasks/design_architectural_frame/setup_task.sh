#!/bin/bash
set -e
echo "=== Setting up design_architectural_frame task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove previous output to ensure deterministic start state
rm -f /home/ga/Documents/FreeCAD/structural_frame.FCStd
rm -f /tmp/structural_analysis.json

# Kill any running FreeCAD instance
kill_freecad

# Launch FreeCAD with a new empty document
# We suppress the Start Center in the environment setup, so this opens a blank doc
echo "Starting FreeCAD..."
launch_freecad

# Wait for FreeCAD window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="