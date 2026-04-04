#!/bin/bash
set -e
echo "=== Setting up design_dovetail_slide task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/FreeCAD/dovetail_slide.FCStd
rm -f /tmp/task_result.json

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any running FreeCAD instance
kill_freecad

# Launch FreeCAD with an empty environment
# We don't load a file, just start the app
echo "Starting FreeCAD..."
launch_freecad

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Dismiss any startup dialogs/Start Center if present
# (user.cfg in environment usually handles this, but we double check)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="