#!/bin/bash
set -e
echo "=== Setting up Crane Lift Plan task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. ensure clean state
# Kill running LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Remove previous output file if it exists
OUTPUT_FILE="/home/ga/Documents/LibreCAD/crane_lift_plan.dxf"
rm -f "$OUTPUT_FILE"

# Create directory if needed
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Start LibreCAD
echo "Starting LibreCAD..."
# Start with empty arguments for a new blank drawing
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad.log 2>&1 &"

# 4. Wait for window and maximize
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize the window (Important for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs (like "Tips of the Day" or "Welcome")
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 5. Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="