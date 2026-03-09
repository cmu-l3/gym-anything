#!/bin/bash
set -e
echo "=== Setting up create_compression_spring task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/FreeCAD/compression_spring.FCStd
rm -f /tmp/task_result.json

# Ensure workspace exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instance
kill_freecad

# Launch FreeCAD with an empty environment
# (Part workbench is default via user.cfg in this env)
echo "Starting FreeCAD..."
launch_freecad

# Wait for window
wait_for_freecad 60

# Maximize and focus (Critical for VLM visibility)
maximize_freecad
sleep 2

# Dismiss any startup dialogs/splash screens if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="