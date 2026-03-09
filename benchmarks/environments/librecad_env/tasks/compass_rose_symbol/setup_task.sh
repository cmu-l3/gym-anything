#!/bin/bash
set -e
echo "=== Setting up compass_rose_symbol task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and is clean
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Remove any previous output file
rm -f /home/ga/Documents/LibreCAD/compass_rose.dxf

# Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Launch LibreCAD with a new empty drawing
# Note: No file argument opens a blank 'Untitled' document
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_launch.log 2>&1 &"
sleep 5

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "librecad\|untitled"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize the window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Ensure focus
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs (like "Welcome") if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="