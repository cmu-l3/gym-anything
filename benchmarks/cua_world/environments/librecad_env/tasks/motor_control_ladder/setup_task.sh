#!/bin/bash
set -e
echo "=== Setting up motor_control_ladder task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create workspace directory if it doesn't exist
mkdir -p /home/ga/Documents/LibreCAD
chown ga:ga /home/ga/Documents/LibreCAD

# Remove previous output file to ensure clean state
rm -f /home/ga/Documents/LibreCAD/motor_control_ladder.dxf

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a blank new drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize the window (Crucial for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="