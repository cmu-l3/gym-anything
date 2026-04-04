#!/bin/bash
set -e
echo "=== Setting up design_ribbed_bracket task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure clean state
pkill -f freecad 2>/dev/null || true
sleep 2

# Create output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove previous output
rm -f /home/ga/Documents/FreeCAD/ribbed_bracket.FCStd

# Start FreeCAD with a new empty document
# We suppress the Start Center via user.cfg in the base image, so it opens empty
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
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="