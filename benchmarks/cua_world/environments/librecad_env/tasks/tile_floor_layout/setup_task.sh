#!/bin/bash
set -e
echo "=== Setting up tile_floor_layout task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure workspace exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Remove any previous output to ensure we grade new work
rm -f /home/ga/Documents/LibreCAD/restroom_tile_layout.dxf

# Kill any existing LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Launch LibreCAD with a blank drawing (no arguments)
# We run as user 'ga' and redirect output to avoid cluttering logs
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# Wait for the window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "librecad\|untitled"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize the window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any potential startup dialogs (like tips or unit selection if not suppressed)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="