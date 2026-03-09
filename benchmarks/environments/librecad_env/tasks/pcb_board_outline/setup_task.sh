#!/bin/bash
set -e
echo "=== Setting up PCB Board Outline task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/LibreCAD/pcb_outline.dxf
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Ensure LibreCAD is running in a clean state
echo "Restarting LibreCAD..."
pkill -f librecad 2>/dev/null || true
sleep 2

# Launch LibreCAD (no file argument = blank drawing)
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# 4. Wait for window and maximize
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "librecad"; then
        echo "LibreCAD detected."
        break
    fi
    sleep 1
done

# Maximize to ensure all tools are visible
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss "Tip of the Day" or startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# 5. Capture initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="