#!/bin/bash
echo "=== Setting up Color Deconvolution task ==="

# Ensure results directory exists
su - ga -c "mkdir -p /home/ga/Fiji_Data/results"

# Clean any previous results
rm -f /home/ga/Fiji_Data/results/channel_1.png 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/channel_2.png 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/channel_1_stats.csv 2>/dev/null || true

# Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
sleep 10

# Wait for Fiji window to appear
echo "Waiting for Fiji window..."
timeout=30
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

# Maximize Fiji window
DISPLAY=:1 wmctrl -r "fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

sleep 2

echo "=== Task setup complete ==="
echo "Fiji is ready for color deconvolution task"
