#!/bin/bash
set -e
echo "=== Setting up road_cross_section task ==="

# 1. Kill any running LibreCAD instances to ensure a clean start
pkill -f librecad 2>/dev/null || true
sleep 2

# 2. Prepare workspace and clean up previous artifacts
mkdir -p /home/ga/Documents/LibreCAD
EXPECTED_FILE="/home/ga/Documents/LibreCAD/road_cross_section.dxf"
rm -f "$EXPECTED_FILE"

# 3. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Start LibreCAD with a blank drawing (no file argument)
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"

# 5. Wait for the window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# 6. Maximize the window (CRITICAL for VLM visibility)
sleep 2
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true
sleep 1

# 8. Dismiss any potential startup dialogs (e.g., tip of the day)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 9. Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="