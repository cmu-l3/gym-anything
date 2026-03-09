#!/bin/bash
set -e
echo "=== Setting up Optical Setup Diagram task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Define output path
OUTPUT_PATH="/home/ga/Documents/LibreCAD/optical_setup.dxf"

# Clean up previous artifacts
rm -f "$OUTPUT_PATH"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a new empty drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize window (Critical for agent visibility)
# Try both specific window name and generic class
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "unnamed - LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs (e.g., Tip of the Day)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="