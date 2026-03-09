#!/bin/bash
set -e
echo "=== Setting up parking_lot_striping task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and has correct permissions
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Remove any previous attempt
rm -f /home/ga/Documents/LibreCAD/parking_lot.dxf

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a new empty drawing
# We don't specify a file, so it opens a blank document
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"
sleep 6

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "librecad"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize the window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (like "Welcome") if they exist
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="