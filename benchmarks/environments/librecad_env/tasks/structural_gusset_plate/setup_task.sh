#!/bin/bash
set -e
echo "=== Setting up Structural Gusset Plate Task ==="

# 1. Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Clean up/Prepare Output Directory
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD
# Remove target file if it exists from previous run
rm -f /home/ga/Documents/LibreCAD/gusset_plate_gp1.dxf

# 4. Start LibreCAD with a blank drawing
# We launch it in background
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad.log 2>&1 &"

# 5. Wait for Window and Maximize
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize to ensure visibility for agent
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Ensure it's focused
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 6. Capture Initial State Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="