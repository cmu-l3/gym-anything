#!/bin/bash
set -e
echo "=== Setting up create_pcb_outline_dxf task ==="

# 1. Kill any running FreeCAD instances
pkill -f freecad 2>/dev/null || true
sleep 2

# 2. Prepare workspace directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# 3. Clean up previous task artifacts to ensure a fresh start
rm -f /home/ga/Documents/FreeCAD/pcb_outline.FCStd
rm -f /home/ga/Documents/FreeCAD/pcb_outline.dxf

# 4. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 5. Launch FreeCAD with a clean empty state
# We use 'su - ga' to run as the user, setting display
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 freecad > /tmp/freecad_task.log 2>&1 &"

# 6. Wait for FreeCAD window to appear
echo "Waiting for FreeCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD" > /dev/null; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done

# 7. Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Create a new document automatically so the agent doesn't have to deal with the Start page
# (Optional, but helps standardize the starting state)
sleep 2
DISPLAY=:1 xdotool key ctrl+n 2>/dev/null || true

# 9. Take initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="