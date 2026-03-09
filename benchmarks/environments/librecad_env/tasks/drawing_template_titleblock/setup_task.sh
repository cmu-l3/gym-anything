#!/bin/bash
set -e
echo "=== Setting up Drawing Template Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous runs
rm -f /home/ga/Documents/LibreCAD/a3_template.dxf
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 2. Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# 3. Start LibreCAD with a clean slate (no file = new drawing)
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad.log 2>&1 &"

# 4. Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done
sleep 2

# 5. Maximize the window (Crucial for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Ensure focus
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true
sleep 1

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="