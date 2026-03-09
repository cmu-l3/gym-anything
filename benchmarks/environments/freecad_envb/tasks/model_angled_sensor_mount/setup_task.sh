#!/bin/bash
set -e
echo "=== Setting up model_angled_sensor_mount task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure FreeCAD is killed and environment is clean
kill_freecad
sleep 2

# Create documents directory and ensure it's empty of target files
mkdir -p /home/ga/Documents/FreeCAD
rm -f /home/ga/Documents/FreeCAD/sensor_mount.FCStd
rm -f /home/ga/Documents/FreeCAD/sensor_mount.stl
chown -R ga:ga /home/ga/Documents/FreeCAD

# Launch FreeCAD
# We launch it empty so the agent starts from a clean slate
echo "Starting FreeCAD..."
launch_freecad

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Configure generic Part Design setup if needed (though default is usually fine)
# Ensure Combo View is visible
DISPLAY=:1 xdotool key --delay 100 v p c 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="