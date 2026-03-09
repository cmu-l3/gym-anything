#!/bin/bash
set -e
echo "=== Setting up Baseball Infield Layout Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Clean up previous attempts
rm -f /home/ga/Documents/LibreCAD/baseball_infield.dxf

# Start LibreCAD
if ! pgrep -f librecad > /dev/null; then
    echo "Starting LibreCAD..."
    su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"
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
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs (e.g., welcome screen)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="