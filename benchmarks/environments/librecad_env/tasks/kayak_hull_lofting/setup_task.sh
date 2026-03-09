#!/bin/bash
echo "=== Setting up Kayak Hull Lofting Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
pkill -f librecad 2>/dev/null || true
sleep 2

OUTPUT_DIR="/home/ga/Documents/LibreCAD"
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/kayak_station_4.dxf"

# Start LibreCAD with a new empty drawing
# We use 'su - ga' to run as the user, ensuring correct permissions and env vars
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD detected."
        break
    fi
    sleep 1
done

# Maximize the window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Capture initial state screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="