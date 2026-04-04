#!/bin/bash
set -e
echo "=== Setting up Conveyor Curve Task ==="

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Cleanup Previous State
rm -f /home/ga/Documents/LibreCAD/conveyor_curve.dxf
pkill -f librecad 2>/dev/null || true
sleep 1

# 3. Ensure Documents directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 4. Start LibreCAD with a blank canvas
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad.log 2>&1 &"

# 5. Wait for Window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window found."
        break
    fi
    sleep 1
done

# 6. Maximize Window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Focus Window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 8. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="