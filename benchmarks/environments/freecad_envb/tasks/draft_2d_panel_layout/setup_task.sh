#!/bin/bash
set -e
echo "=== Setting up draft_2d_panel_layout task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
pkill -f freecad 2>/dev/null || true
sleep 2

# Create workspace directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove any previous result file
rm -f /home/ga/Documents/FreeCAD/panel_layout.FCStd

# Launch FreeCAD
# We launch it empty so the user has to create the new document and switch workbenches
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "FreeCAD"; then
        echo "FreeCAD window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="