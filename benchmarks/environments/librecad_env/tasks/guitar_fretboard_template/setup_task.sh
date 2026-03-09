#!/bin/bash
echo "=== Setting up Guitar Fretboard Template Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
pkill -f librecad 2>/dev/null || true
sleep 2

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/LibreCAD
rm -f /home/ga/Documents/LibreCAD/fretboard_template.dxf
chown -R ga:ga /home/ga/Documents/LibreCAD

# Start LibreCAD with a fresh empty state
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_launch.log 2>&1 &"

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

# Focus window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs (Esc key)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="