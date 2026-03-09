#!/bin/bash
set -e
echo "=== Setting up design_thin_wrench task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous runs
rm -f /home/ga/Documents/FreeCAD/cone_wrench.FCStd
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instance
pkill -f freecad 2>/dev/null || true
sleep 2

# Launch FreeCAD
# Using the pre-configured environment which suppresses start center
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD"; then
        echo "FreeCAD window detected"
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# Switch to Part Design workbench implies creating a new body, but we'll let the agent decide 
# between Part or PartDesign. We just ensure the app is focused.

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="