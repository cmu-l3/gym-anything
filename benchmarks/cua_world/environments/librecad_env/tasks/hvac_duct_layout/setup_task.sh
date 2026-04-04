#!/bin/bash
set -e
echo "=== Setting up HVAC Duct Layout task ==="

# 1. Anti-gaming: Record start time
date +%s > /tmp/task_start_time.txt

# 2. Cleanup: Remove previous output
OUTPUT_PATH="/home/ga/Documents/LibreCAD/hvac_duct_layout.dxf"
rm -f "$OUTPUT_PATH"
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Start Application: LibreCAD
# Kill any existing instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with no arguments (blank drawing)
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"

# 4. Wait for Window and Maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window found."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 5. Dismiss any startup dialogs (just in case)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture Initial State Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="