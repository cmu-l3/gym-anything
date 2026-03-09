#!/bin/bash
set -e
echo "=== Setting up bolt_circle_plate task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous attempts
rm -f /home/ga/Documents/LibreCAD/bolt_circle_plate.dxf
# Ensure workspace exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Ensure LibreCAD is running
if ! pgrep -f "librecad" > /dev/null; then
    echo "Starting LibreCAD..."
    # Start with no file (new drawing)
    su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_launch.log 2>&1 &"
    sleep 8
fi

# 4. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "librecad"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize window (critical for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 5. Dismiss any startup dialogs (e.g. Tips)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="