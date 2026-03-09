#!/bin/bash
set -e
echo "=== Setting up Fractal Dimension Analysis task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create output directories with correct permissions
mkdir -p /home/ga/Fiji_Data/results/fractal
chown -R ga:ga /home/ga/Fiji_Data/

# Remove previous results to ensure clean state
rm -f /home/ga/Fiji_Data/results/fractal/fractal_results.csv
rm -f /home/ga/Fiji_Data/results/fractal/fractal_plot.png
rm -f /tmp/fractal_task_result.json

# Launch Fiji if not running
if ! pgrep -f "fiji" > /dev/null && ! pgrep -f "ImageJ" > /dev/null; then
    echo "Starting Fiji..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|Fiji"; then
            echo "Fiji window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize Fiji window
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "ImageJ" 2>/dev/null || \
DISPLAY=:1 wmctrl -a "Fiji" 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="