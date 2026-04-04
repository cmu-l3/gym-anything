#!/bin/bash
set -e
echo "=== Setting up create_loft_transition task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running FreeCAD instance
pkill -f freecad 2>/dev/null || true
sleep 2

# Ensure clean workspace
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove any previous task output to ensure a clean slate
rm -f /home/ga/Documents/FreeCAD/loft_transition.FCStd

# Launch FreeCAD with a new empty document
# Using nohup and disown to ensure it stays running
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for FreeCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD" > /dev/null; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done

# Wait a bit for initialization
sleep 5

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# Ensure Part Design workbench is likely to be used, but we leave the user to select it
# We just ensure the Start page is dismissed if present (by creating new doc if needed)
# The user.cfg in the environment setup suppresses the start center, but we double check.
# Sending Ctrl+N ensures a new document is open
DISPLAY=:1 xdotool key ctrl+n 2>/dev/null || true
sleep 2

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="