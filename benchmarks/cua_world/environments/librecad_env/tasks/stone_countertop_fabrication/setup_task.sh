#!/bin/bash
set -e
echo "=== Setting up Stone Countertop Task ==="

# 1. Kill any running LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/LibreCAD/countertop.dxf
rm -f /tmp/task_result.json
rm -f /tmp/dxf_analysis.json

# 3. Ensure workspace directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 4. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Start LibreCAD
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# 6. Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# 7. Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 8. Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="