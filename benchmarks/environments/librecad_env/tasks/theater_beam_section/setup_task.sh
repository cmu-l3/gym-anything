#!/bin/bash
set -e
echo "=== Setting up theater_beam_section task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous run artifacts
rm -f /home/ga/Documents/LibreCAD/beam_study.dxf
rm -f /tmp/task_result.json
rm -f /tmp/task_final.png

# 3. Ensure LibreCAD is not running
pkill -f librecad 2>/dev/null || true
sleep 1

# 4. Start LibreCAD with a new empty drawing
# We start it without arguments to get a blank slate
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# 5. Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# 6. Maximize the window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 8. Dismiss any startup dialogs (like "Welcome") if they exist
# Press Esc a couple of times just in case
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="