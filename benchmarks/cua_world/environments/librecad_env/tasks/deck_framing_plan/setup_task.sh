#!/bin/bash
set -e
echo "=== Setting up deck_framing_plan task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/LibreCAD/deck_framing_plan.dxf
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Kill existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# 4. Launch LibreCAD with a clean new drawing
# We start it in the background
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for LibreCAD..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "librecad\|untitled"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# 6. Maximize window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 7. Dismiss any startup dialogs (Esc key usually works)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="