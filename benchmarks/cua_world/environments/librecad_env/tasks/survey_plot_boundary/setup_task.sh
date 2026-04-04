#!/bin/bash
set -e
echo "=== Setting up survey_plot_boundary task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/LibreCAD/survey_plot.dxf
rm -f /tmp/dxf_analysis.json
rm -f /tmp/task_result.json

# 3. Ensure workspace directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 4. Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# 5. Launch LibreCAD with a new empty drawing
echo "Launching LibreCAD..."
# We launch without arguments to start with a blank "Untitled" drawing
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"

# 6. Wait for window and ensure it's ready
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "librecad"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# 7. Maximize and focus the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -x -a "librecad" 2>/dev/null || true

# 8. Dismiss startup dialogs if they appear (First Run wizard should be suppressed by env setup, but just in case)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="