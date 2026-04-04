#!/bin/bash
set -e
echo "=== Setting up Spindle Elongation Kinetics task ==="

# 1. Create results directory
# Using 'su - ga -c' to ensure correct permissions/user context
su - ga -c "mkdir -p /home/ga/Fiji_Data/results/spindle"

# 2. Clean previous artifacts
rm -f /home/ga/Fiji_Data/results/spindle/spindle_projection.tif 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/spindle/velocity_report.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 3. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time

# 4. Launch Fiji
echo "Launching Fiji..."
# Check if Fiji is already running, if not launch it
if ! pgrep -f "fiji" > /dev/null && ! pgrep -f "ImageJ" > /dev/null; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
    
    # Wait for window to appear
    echo "Waiting for Fiji to start..."
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|Fiji"; then
            echo "Fiji window detected."
            break
        fi
        sleep 1
    done
else
    echo "Fiji is already running."
fi

# 5. Ensure window is maximized for visibility
sleep 2
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="