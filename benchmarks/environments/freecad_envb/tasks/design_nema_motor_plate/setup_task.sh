#!/bin/bash
set -e
echo "=== Setting up design_nema_motor_plate task ==="

# 1. Cleanup previous run artifacts
pkill -f freecad 2>/dev/null || true
sleep 2

TARGET_DIR="/home/ga/Documents/FreeCAD"
mkdir -p "$TARGET_DIR"
rm -f "$TARGET_DIR/nema_plate.FCStd"
chown -R ga:ga "$TARGET_DIR"

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Start FreeCAD
# We start it empty. The user.cfg in the environment sets PartWorkbench as default,
# but the task requires PartDesign. The agent should know to switch.
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 freecad > /tmp/freecad_task.log 2>&1 &"

# 4. Wait for window and maximize
echo "Waiting for FreeCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD"; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done

# Maximize the window to ensure all toolbars are visible
sleep 2
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="