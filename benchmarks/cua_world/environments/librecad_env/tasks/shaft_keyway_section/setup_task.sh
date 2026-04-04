#!/bin/bash
set -e
echo "=== Setting up shaft_keyway_section task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and has correct permissions
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Remove any previous attempt to ensure a clean start
rm -f /home/ga/Documents/LibreCAD/shaft_keyway_section.dxf

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Launch LibreCAD with a new blank drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "librecad"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize the window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs (like "Tip of the Day" or unit selection if it appears)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="