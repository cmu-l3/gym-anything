#!/bin/bash
set -e
echo "=== Setting up design_v_block_jig task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory and remove previous files
mkdir -p /home/ga/Documents/FreeCAD
rm -f /home/ga/Documents/FreeCAD/v_block.FCStd
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any running FreeCAD instances
pkill -f freecad 2>/dev/null || true
sleep 2

# Launch FreeCAD with a new empty document
# We use 'sh -c' to ensure environment variables are set correctly for the user
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for FreeCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD" > /dev/null; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# Create a new document automatically to save the agent a step (optional but helpful for consistent state)
# Simulate Ctrl+N
sleep 5
DISPLAY=:1 xdotool key ctrl+n 2>/dev/null || true
sleep 1

# Ensure Part Design or Part workbench is likely to be used, but we leave it to agent preferences.
# Just ensure the start page is dismissed if it appeared.

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="