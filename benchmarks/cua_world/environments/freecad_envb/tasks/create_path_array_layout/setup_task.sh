#!/bin/bash
set -e
echo "=== Setting up create_path_array_layout task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Kill any running FreeCAD instance
pkill -f freecad 2>/dev/null || true
sleep 2

# Ensure clean workspace and output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove previous output to ensure deterministic start state
rm -f /home/ga/Documents/FreeCAD/curved_colonnade.FCStd

# Launch FreeCAD with an empty document
# We suppress the Start Center via user.cfg in the base environment, 
# so this opens a blank workspace.
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD window to appear
echo "Waiting for FreeCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD"; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done

# Maximize the window to ensure toolbars are visible
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Ensure a new document is ready (Ctrl+N)
# Even if one opens by default, a second blank one doesn't hurt and ensures state
DISPLAY=:1 xdotool key ctrl+n 2>/dev/null || true
sleep 1

# Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="