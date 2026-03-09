#!/bin/bash
set -e
echo "=== Setting up Isometric Fire Riser task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create workspace directory if it doesn't exist
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents

# Clean up any previous attempts
rm -f /home/ga/Documents/LibreCAD/fire_riser_iso.dxf

# Ensure LibreCAD is not running
pkill -f librecad 2>/dev/null || true
sleep 1

# Start LibreCAD with a clean slate (no file)
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize the window (Critical for agent visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any potential "Tip of the Day" or startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="