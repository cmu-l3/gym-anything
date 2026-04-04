#!/bin/bash
set -e
echo "=== Setting up evacuation_map_update task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous runs
rm -f /home/ga/Documents/LibreCAD/evacuation_plan.dxf
rm -f /tmp/dxf_analysis.json
rm -f /tmp/task_result.json

# Ensure Documents directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents

# Ensure the real floorplan exists (from environment setup)
if [ ! -f "/opt/librecad_samples/floorplan.dxf" ]; then
    echo "ERROR: Sample floorplan.dxf not found in /opt/librecad_samples"
    exit 1
fi

# Copy fresh floorplan for this task
cp /opt/librecad_samples/floorplan.dxf /home/ga/Documents/LibreCAD/floorplan.dxf
chown ga:ga /home/ga/Documents/LibreCAD/floorplan.dxf

# Start LibreCAD with the file loaded
if ! pgrep -f "librecad" > /dev/null; then
    echo "Starting LibreCAD..."
    su - ga -c "DISPLAY=:1 librecad /home/ga/Documents/LibreCAD/floorplan.dxf &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
            echo "LibreCAD window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Dismiss any startup dialogs if they appear (e.g., tip of the day)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="