#!/bin/bash
set -e
echo "=== Setting up Pear-Shaped Cam Profile task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous attempts
rm -f /home/ga/Documents/LibreCAD/cam_profile.dxf
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Start LibreCAD with a clean slate
# Kill any existing instances
pkill -f librecad 2>/dev/null || true
sleep 2

echo "Starting LibreCAD..."
# Start without a file argument to get a blank drawing
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# 4. Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# 5. Maximize the window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="