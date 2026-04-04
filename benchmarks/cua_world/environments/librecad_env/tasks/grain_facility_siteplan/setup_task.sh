#!/bin/bash
set -e
echo "=== Setting up Grain Facility Site Plan Task ==="

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/LibreCAD/grain_facility.dxf
rm -f /tmp/dxf_analysis.json
rm -f /tmp/task_result.json

# Ensure document directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents

# 2. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Start LibreCAD with a clean slate (no file)
echo "Starting LibreCAD..."
if ! pgrep -f librecad > /dev/null; then
    su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"
    
    # Wait for window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
            echo "LibreCAD window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 4. Maximize window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Focus window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="