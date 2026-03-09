#!/bin/bash
set -e
echo "=== Setting up Microplate Calibration Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and has correct permissions
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents

# Remove any existing output file to ensure a clean start
rm -f /home/ga/Documents/LibreCAD/microplate_template.dxf

# Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 1

# Start LibreCAD with a new empty drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad.log 2>&1 &"

# Wait for window to appear
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

# Dismiss any startup dialogs (e.g., Tip of the Day)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="