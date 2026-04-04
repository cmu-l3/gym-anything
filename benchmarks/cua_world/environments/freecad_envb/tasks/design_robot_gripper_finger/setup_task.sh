#!/bin/bash
set -e
echo "=== Setting up design_robot_gripper_finger task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state
rm -f /home/ga/Documents/FreeCAD/gripper_finger.FCStd
rm -f /tmp/task_result.json

# Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instances
pkill -f freecad 2>/dev/null || true
sleep 2

# Start FreeCAD
echo "Starting FreeCAD..."
# Use su to run as ga user, setting display and authority
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for FreeCAD window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD" > /dev/null; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done

# Small delay to ensure UI is responsive
sleep 5

# Maximize window (CRITICAL for agent visibility)
# Try specific window title first, then active window
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# Dismiss start center if it appears (handled by user.cfg usually, but good to be safe)
# Create new document shortcut (Ctrl+N) just in case
DISPLAY=:1 xdotool key ctrl+n 2>/dev/null || true

# Take screenshot of initial state (for evidence)
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="