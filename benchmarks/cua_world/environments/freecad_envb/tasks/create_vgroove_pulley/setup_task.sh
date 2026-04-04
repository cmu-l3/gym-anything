#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_vgroove_pulley task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts to ensure clean state
rm -f /home/ga/Documents/FreeCAD/vgroove_pulley.FCStd
rm -f /home/ga/Documents/FreeCAD/vgroove_pulley.step
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instance
kill_freecad
sleep 2

# Launch FreeCAD with no file (empty session)
# Using generic launch_freecad function from env or direct command
su - ga -c "DISPLAY=:1 freecad > /tmp/freecad_task.log 2>&1 &"
sleep 5

# Wait for FreeCAD window to appear
wait_for_freecad 45

# Give extra time for startup dialogs/rendering
sleep 5

# Maximize and focus the FreeCAD window
maximize_freecad
sleep 2

# Dismiss any startup dialogs (Start Center etc)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="