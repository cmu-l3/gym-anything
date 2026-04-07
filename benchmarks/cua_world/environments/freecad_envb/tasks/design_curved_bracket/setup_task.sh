#!/bin/bash
set -e
echo "=== Setting up design_curved_bracket task ==="

source /workspace/scripts/task_utils.sh

# Clean any previous output to ensure a fresh start
rm -f /home/ga/Documents/FreeCAD/curved_bracket.FCStd
rm -f /home/ga/Documents/FreeCAD/curved_bracket.step
rm -f /home/ga/Documents/FreeCAD/curved_bracket.stp
rm -f /tmp/task_result.json
rm -f /tmp/design_curved_bracket_result.json

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

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

echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"
echo "=== Task setup complete ==="
echo "FreeCAD is running with an empty window."
echo "Active windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
