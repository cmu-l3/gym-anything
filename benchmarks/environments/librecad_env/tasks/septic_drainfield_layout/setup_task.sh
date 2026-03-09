#!/bin/bash
set -e
echo "=== Setting up septic_drainfield_layout task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create workspace directory if it doesn't exist
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Clean up previous artifacts
rm -f /home/ga/Documents/LibreCAD/septic_plan.dxf
rm -f /tmp/dxf_analysis.json

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs (e.g. Tips) if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="