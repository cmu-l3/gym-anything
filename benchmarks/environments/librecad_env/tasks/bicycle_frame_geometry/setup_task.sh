#!/bin/bash
set -e
echo "=== Setting up bicycle_frame_geometry task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/LibreCAD
rm -f /home/ga/Documents/LibreCAD/bicycle_geometry.dxf

# Set permissions
chown -R ga:ga /home/ga/Documents/LibreCAD

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a new empty drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs (like "Welcome") if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="