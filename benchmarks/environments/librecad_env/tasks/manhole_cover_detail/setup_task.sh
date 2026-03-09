#!/bin/bash
set -e
echo "=== Setting up Manhole Detail Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define output path
OUTPUT_PATH="/home/ga/Documents/LibreCAD/manhole_detail.dxf"

# Clean up previous attempts
rm -f "$OUTPUT_PATH"
# Ensure directory exists and is owned by ga
mkdir -p "$(dirname "$OUTPUT_PATH")"
chown -R ga:ga "$(dirname "$OUTPUT_PATH")"

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a new empty drawing
# We don't load a file; we want a blank slate.
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_launch.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize the window (CRITICAL for visual verification and agent action space)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs (like "Welcome" or "Tips") if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="