#!/bin/bash
set -e
echo "=== Setting up model_turbine_blade task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create workspace directory if it doesn't exist
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove any previous task file to ensure clean state
rm -f /home/ga/Documents/FreeCAD/turbine_blade.FCStd

# Kill any existing FreeCAD instances
kill_freecad

# Launch FreeCAD with a new empty document
# We rely on the user.cfg in the environment to suppress the Start Center
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD window
wait_for_freecad 30

# Maximize the window
maximize_freecad

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="