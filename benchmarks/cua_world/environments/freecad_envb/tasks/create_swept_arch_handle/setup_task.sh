#!/bin/bash
set -e
echo "=== Setting up create_swept_arch_handle task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean any previous output to ensure a fresh start
rm -f /home/ga/Documents/FreeCAD/display_handle.FCStd
rm -f /home/ga/Documents/FreeCAD/display_handle.step
rm -f /tmp/task_result.json

# Ensure workspace directory exists and has correct permissions
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instance
kill_freecad
sleep 2

# Launch FreeCAD (empty, no file)
echo "Launching FreeCAD..."
launch_freecad
sleep 10

# Wait for window to appear
wait_for_freecad 60

# Maximize window (CRITICAL for agent visibility)
maximize_freecad
sleep 2

# Dismiss any startup dialogs (like the Start Center if not suppressed)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="