#!/bin/bash
set -e
echo "=== Setting up solar_array_plan task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define output path
OUTPUT_PATH="/home/ga/Documents/LibreCAD/solar_array_plan.dxf"

# Remove any previous output file to ensure clean state
rm -f "$OUTPUT_PATH"

# Ensure workspace directory exists and is owned by user
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a new blank drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_startup.log 2>&1 &"

# Wait for LibreCAD window to appear
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "librecad"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Dismiss any startup dialogs (tips, welcome, etc.)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Maximize the window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="