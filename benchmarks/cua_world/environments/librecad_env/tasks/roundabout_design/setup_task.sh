#!/bin/bash
set -e
echo "=== Setting up Roundabout Design Task ==="

# 1. Prepare Directory
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 2. Cleanup previous runs
rm -f /home/ga/Documents/LibreCAD/roundabout_design.dxf
rm -f /tmp/dxf_analysis.json
rm -f /tmp/task_result.json

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Start LibreCAD with a blank drawing
# We don't load a file, just start the app
if ! pgrep -f "librecad" > /dev/null; then
    echo "Starting LibreCAD..."
    su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"
    sleep 5
fi

# 5. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window found."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 6. Initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="