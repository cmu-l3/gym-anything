#!/bin/bash
set -e
echo "=== Setting up design_fitted_box_lid task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory and remove previous files
mkdir -p /home/ga/Documents/FreeCAD
rm -f /home/ga/Documents/FreeCAD/project_box_assembly.FCStd
rm -f /tmp/geometry_analysis.json

# Kill any running FreeCAD instance
kill_freecad

# Launch FreeCAD with a new empty document
# We rely on the user.cfg in setup_freecad.sh to suppress start center
echo "Starting FreeCAD..."
launch_freecad

# Wait for FreeCAD window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Create a new document automatically to save the agent one click
# and ensure we start in a clean state
echo "Creating new document..."
DISPLAY=:1 xdotool key ctrl+n
sleep 2

# Ensure Part Design workbench is selectable or active
# (Optional, as agent should know how to switch, but helps consistency)

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="