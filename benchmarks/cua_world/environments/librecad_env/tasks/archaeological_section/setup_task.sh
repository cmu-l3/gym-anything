#!/bin/bash
echo "=== Setting up archaeological_section task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create workspace directory
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Clean up previous artifacts
rm -f /home/ga/Documents/LibreCAD/section_drawing.dxf

# Ensure LibreCAD is not running
pkill -f librecad 2>/dev/null || true
sleep 1

# Start LibreCAD with a blank drawing (no arguments)
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs (e.g. Tips)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="