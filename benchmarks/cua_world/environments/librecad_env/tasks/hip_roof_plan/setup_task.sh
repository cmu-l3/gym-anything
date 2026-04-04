#!/bin/bash
set -e
echo "=== Setting up Hip Roof Plan task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous runs
rm -f /home/ga/Documents/LibreCAD/hip_roof_plan.dxf
rm -f /tmp/dxf_analysis.json
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Ensure LibreCAD is running cleanly
# Kill existing instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a blank drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_startup.log 2>&1 &"

# 4. Wait for window and maximize
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD detected."
        break
    fi
    sleep 1
done

# Maximize the window (Critical for agent visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 5. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="