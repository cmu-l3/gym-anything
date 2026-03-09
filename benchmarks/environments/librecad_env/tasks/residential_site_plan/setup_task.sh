#!/bin/bash
set -e
echo "=== Setting up residential_site_plan task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state
# Kill any running LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 1

# Remove any previous output file
OUTPUT_FILE="/home/ga/Documents/LibreCAD/residential_site_plan.dxf"
if [ -f "$OUTPUT_FILE" ]; then
    rm "$OUTPUT_FILE"
    echo "Removed previous output file."
fi

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Start LibreCAD
echo "Starting LibreCAD..."
# We start it without arguments to get a blank drawing
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# 4. Wait for window
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD detected."
        break
    fi
    sleep 1
done

# 5. Maximize and Focus
# Critical for agent visibility
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2 # Allow UI to render
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="