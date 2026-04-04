#!/bin/bash
set -e
echo "=== Setting up Hyperstack Reconstruction Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure results directory exists
mkdir -p /home/ga/Fiji_Data/results/
chown ga:ga /home/ga/Fiji_Data/results/

# Clean previous results
rm -f /home/ga/Fiji_Data/results/reconstructed_hyperstack.tif
rm -f /tmp/hyperstack_result.json

# Ensure Fiji is running
if ! pgrep -f "fiji" > /dev/null && ! pgrep -f "ImageJ" > /dev/null; then
    echo "Starting Fiji..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ"; then
            echo "Fiji window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize Fiji
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus Fiji
DISPLAY=:1 wmctrl -a "Fiji" 2>/dev/null || \
DISPLAY=:1 wmctrl -a "ImageJ" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="