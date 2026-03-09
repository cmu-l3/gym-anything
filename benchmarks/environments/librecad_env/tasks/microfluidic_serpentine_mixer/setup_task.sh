#!/bin/bash
set -e
echo "=== Setting up Microfluidic Serpentine Mixer Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
rm -f /home/ga/Documents/LibreCAD/microfluidic_chip.dxf
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a blank canvas
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="