#!/bin/bash
set -e
echo "=== Setting up custom_macropad_plate task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/LibreCAD
rm -f /home/ga/Documents/LibreCAD/macropad_plate.dxf

# Start LibreCAD
if ! pgrep -f "librecad" > /dev/null; then
    echo "Starting LibreCAD..."
    su - ga -c "DISPLAY=:1 librecad > /tmp/librecad.log 2>&1 &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs/splash screens if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="