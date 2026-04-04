#!/bin/bash
set -e
echo "=== Setting up create_shelled_enclosure task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any previous output to ensure clean state
rm -f /home/ga/Documents/FreeCAD/enclosure.FCStd

# Ensure workspace directory exists and has correct permissions
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instances
kill_freecad
sleep 2

# Launch FreeCAD with a blank session (no file loaded)
# The setup_freecad.sh script has already configured user.cfg to suppress the Start Center
launch_freecad
sleep 10

# Wait for FreeCAD window to appear
wait_for_freecad 60

# Maximize the window (Critical for agent visibility)
maximize_freecad
sleep 2

# Dismiss any potential startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="