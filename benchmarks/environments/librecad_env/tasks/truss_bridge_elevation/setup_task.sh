#!/bin/bash
set -e
echo "=== Setting up truss_bridge_elevation task ==="

# 1. Anti-gaming initialization
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
rm -f /home/ga/Documents/LibreCAD/truss_elevation.dxf
rm -f /tmp/truss_analysis.json
rm -f /tmp/task_result.json

# 3. Ensure workspace exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents

# 4. Launch LibreCAD (Desktop App Setup Pattern)
# Kill any existing instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a blank drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "librecad"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss startup dialogs if they appear (Esc key)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 5. Capture initial state
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="