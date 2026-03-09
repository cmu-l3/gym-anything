#!/bin/bash
set -e
echo "=== Setting up Create Involute Spur Gear Task ==="

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Clean Environment
# Kill running instances
pkill -f freecad 2>/dev/null || true
sleep 2

# Clean previous output
OUTPUT_FILE="/home/ga/Documents/FreeCAD/spur_gear.FCStd"
rm -f "$OUTPUT_FILE"
mkdir -p "$(dirname "$OUTPUT_FILE")"
chown -R ga:ga /home/ga/Documents/FreeCAD

# 3. Start FreeCAD
# Launch with empty document
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# 4. Wait for Window and Maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD"; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize the window to ensure UI elements are visible to the agent
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Capture Initial State Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="