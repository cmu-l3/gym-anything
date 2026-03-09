#!/bin/bash
echo "=== Setting up Retaining Wall Section task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD
rm -f /home/ga/Documents/LibreCAD/retaining_wall_section.dxf

# Start LibreCAD with a new empty drawing
# We do NOT load an existing file because the task is to draw from scratch
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize the window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
# Ensure focus
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any potential startup dialogs/tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="