#!/bin/bash
set -e
echo "=== Setting up create_shaft_keyway task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Remove any previous output
rm -f /home/ga/Documents/FreeCAD/drive_shaft_keyway.FCStd

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instance
kill_freecad

# Launch FreeCAD with a blank document
# We launch it via su - ga to ensure correct user context
echo "Launching FreeCAD..."
launch_freecad

# Wait for FreeCAD window to appear
wait_for_freecad 45

# Give FreeCAD time to fully initialize
sleep 8

# Maximize the window (CRITICAL for agent visibility)
maximize_freecad
sleep 2

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state (for evidence)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="