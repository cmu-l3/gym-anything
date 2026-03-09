#!/bin/bash
echo "=== Setting up Orthographic V-Block Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create workspace directory if it doesn't exist
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Clean up previous output
rm -f /home/ga/Documents/LibreCAD/vblock_projection.dxf

# Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a clean slate
# We explicitly don't load a file so it starts with a new empty drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_launch.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize window (Critical for VLM)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss startup dialogs if any (Enter usually clears the "Welcome" or "Unit" dialog)
sleep 2
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="