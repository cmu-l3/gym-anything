#!/bin/bash
set -e
echo "=== Setting up design_radial_impeller task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running FreeCAD instance
kill_freecad

# Clean up previous task artifacts
rm -f /home/ga/Documents/FreeCAD/radial_impeller.FCStd
rm -f /tmp/geometry_report.json
rm -f /tmp/task_result.json

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Launch FreeCAD (empty state)
echo "Starting FreeCAD..."
launch_freecad

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Configure UI - Ensure Combo View is visible for Part Design workflow
# (Note: This uses xdotool coordinates which might be resolution dependent, 
# but generic keyboard shortcuts are safer if available. FreeCAD default is often fine.)
# We will focus the main window to be safe.
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="