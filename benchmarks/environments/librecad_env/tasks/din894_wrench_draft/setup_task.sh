#!/bin/bash
set -e
echo "=== Setting up DIN 894 Wrench Task ==="

# 1. Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous output
OUTPUT_FILE="/home/ga/Documents/LibreCAD/din894_wrench.dxf"
rm -f "$OUTPUT_FILE"

# 4. Ensure output directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 5. Start LibreCAD with a blank drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad.log 2>&1 &"

# 6. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window found."
        break
    fi
    sleep 1
done
sleep 2

# Maximize the window (CRITICAL for visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="