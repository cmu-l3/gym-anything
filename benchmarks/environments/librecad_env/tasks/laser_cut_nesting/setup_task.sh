#!/bin/bash
echo "=== Setting up laser_cut_nesting task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Remove previous output file to ensure clean state
rm -f /home/ga/Documents/LibreCAD/gasket_nesting.dxf

# Kill any existing LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a new empty drawing
# We run as user 'ga' and set the display
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs (e.g. "Tip of the Day")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="