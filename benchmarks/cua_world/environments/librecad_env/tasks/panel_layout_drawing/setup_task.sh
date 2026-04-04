#!/bin/bash
set -e
echo "=== Setting up panel_layout_drawing task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state
# Kill running instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Remove previous output file
OUTPUT_FILE="/home/ga/Documents/LibreCAD/control_panel_layout.dxf"
rm -f "$OUTPUT_FILE"

# Create directory if missing
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Start LibreCAD with a clean empty drawing
# We do NOT load the floorplan sample here; this task starts from scratch
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"

# 4. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
# Focus window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 5. Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="