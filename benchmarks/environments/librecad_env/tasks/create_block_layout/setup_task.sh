#!/bin/bash
set -e
echo "=== Setting up create_block_layout task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any previous output file to ensure clean state
rm -f /home/ga/Documents/LibreCAD/store_layout.dxf

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a blank drawing
# Note: No file argument means start with default empty drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_startup.log 2>&1 &"
sleep 6

# Wait for LibreCAD window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "librecad"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize window (Critical for agent visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (e.g., Tips, Welcome) if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="