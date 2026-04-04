#!/bin/bash
set -e
echo "=== Setting up model_clevis_rod_end task ==="

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Kill any running FreeCAD instance
kill_freecad

# Clean up previous attempts
rm -f /home/ga/Documents/FreeCAD/clevis_rod_end.FCStd
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Launch FreeCAD with a new empty document
# We suppress the Start Center via user.cfg in env setup, so this opens an empty UI
echo "Starting FreeCAD..."
launch_freecad

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Create a new document automatically to save the agent a step/ensure clean state
DISPLAY=:1 xdotool key ctrl+n
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="