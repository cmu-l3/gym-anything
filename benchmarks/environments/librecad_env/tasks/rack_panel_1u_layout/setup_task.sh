#!/bin/bash
set -e
echo "=== Setting up rack_panel_1u_layout task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create documents directory if it doesn't exist
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents

# Clean up any previous attempts
rm -f /home/ga/Documents/LibreCAD/rack_panel.dxf
rm -f /tmp/task_result.json

# Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Start LibreCAD with a new empty drawing
# Note: No file argument means start with default template (usually empty)
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_launch.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize window (CRITICAL for agent visibility)
# Try both specific window name and class to be robust
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "unnamed" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any potential startup dialogs (like "Tip of the Day")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="