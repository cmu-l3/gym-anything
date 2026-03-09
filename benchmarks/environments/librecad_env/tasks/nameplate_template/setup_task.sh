#!/bin/bash
set -e
echo "=== Setting up Nameplate Template Task ==="

# 1. Record task start time for anti-gaming (file modification check)
date +%s > /tmp/task_start_time.txt

# 2. Prepare the environment
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Clean up any previous attempts
rm -f /home/ga/Documents/LibreCAD/nameplate_template.dxf

# 4. Kill any running LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# 5. Start LibreCAD with a clean slate (no arguments = new drawing)
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# 6. Wait for window to appear
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "librecad"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# 7. Maximize the window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 8. Dismiss startup dialogs if they appear (Welcome screen / Unit setup)
# Press Escape a few times to clear wizards
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
# Press Enter just in case a default dialog is focused
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# 9. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="