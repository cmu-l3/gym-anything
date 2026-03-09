#!/bin/bash
set -e
echo "=== Setting up Water Well Section task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create documents directory if it doesn't exist
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents

# Clean up any previous output file to ensure we detect new work
OUTPUT_FILE="/home/ga/Documents/LibreCAD/water_well_section.dxf"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing previous output file..."
    rm -f "$OUTPUT_FILE"
fi

# Ensure LibreCAD is not running
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a blank drawing
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

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs (Esc key usually works)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="