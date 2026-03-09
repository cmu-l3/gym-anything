#!/bin/bash
set -e
echo "=== Setting up design_control_knob task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_freecad
rm -f /home/ga/Documents/FreeCAD/control_knob.FCStd
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Launch FreeCAD with a new empty document
# We rely on user.cfg from environment setup to suppress Start Center
echo "Starting FreeCAD..."
launch_freecad

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Ensure Part Design workbench is ready (optional, but good practice)
# We won't force it via script to allow agent to choose, but we ensure window is ready.
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="