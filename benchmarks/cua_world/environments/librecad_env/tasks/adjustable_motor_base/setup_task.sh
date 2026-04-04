#!/bin/bash
set -e
echo "=== Setting up adjustable_motor_base task ==="

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state
# Kill running instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Clean workspace
rm -f /home/ga/Documents/LibreCAD/motor_base_plate.dxf 2>/dev/null || true
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Start LibreCAD with a blank drawing
# We launch it without a file argument to get a fresh untitled document
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad.log 2>&1 &"

# 4. Wait for window and maximize
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize window (Crucial for agent visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true
sleep 2

# Dismiss any startup tips/dialogs if they appear (Esc key)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="