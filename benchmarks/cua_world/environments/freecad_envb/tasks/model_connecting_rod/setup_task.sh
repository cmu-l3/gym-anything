#!/bin/bash
set -e
echo "=== Setting up model_connecting_rod task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_freecad
mkdir -p /home/ga/Documents/FreeCAD
rm -f /home/ga/Documents/FreeCAD/connecting_rod.FCStd

# Start FreeCAD with a blank document
# We launch it empty so the user has to create the new document or start modeling
echo "Starting FreeCAD..."
launch_freecad

# Wait for window
wait_for_freecad 30

# Maximize
maximize_freecad

# Create a new document automatically to save the agent one click (optional but helpful for consistency)
# sending Ctrl+N
echo "Creating new document..."
sleep 2
DISPLAY=:1 xdotool key ctrl+n
sleep 1

# Select Part Design workbench (common for this type of task)
# This is a helper; agent can switch if they want.
# We won't force it hard, but usually it helps set context.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="