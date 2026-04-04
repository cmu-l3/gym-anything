#!/bin/bash
set -e
echo "=== Setting up Mitotic Spindle Tracking task ==="

# 1. Create results directory
mkdir -p /home/ga/Fiji_Data/results/tracking
chown -R ga:ga /home/ga/Fiji_Data/results

# 2. Clean previous results
rm -f /home/ga/Fiji_Data/results/tracking/spindle_intensity.csv

# 3. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch Fiji
echo "Launching Fiji..."
if [ -f "/home/ga/launch_fiji.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
else
    su - ga -c "DISPLAY=:1 fiji" &
fi

# 5. Wait for Fiji window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ"; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# 6. Maximize window
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="