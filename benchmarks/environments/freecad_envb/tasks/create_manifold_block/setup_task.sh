#!/bin/bash
set -e
echo "=== Setting up create_manifold_block task ==="

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/FreeCAD/manifold_block.FCStd
rm -f /tmp/task_result.json
rm -f /tmp/geometry_analysis.json

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure destination directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# 4. Start FreeCAD
# We start with a fresh instance to ensure clean state
pkill -f freecad 2>/dev/null || true
sleep 2

echo "Starting FreeCAD..."
# Start minimal FreeCAD (Part workbench is default via user.cfg in env)
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_launch.log 2>&1 &"

# 5. Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD" > /dev/null; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done

# 6. Maximize window for visibility
sleep 2
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Create a new document automatically to save agent a step/clicks
# This ensures we start in a ready state.
DISPLAY=:1 xdotool key ctrl+n
sleep 1

# 8. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="