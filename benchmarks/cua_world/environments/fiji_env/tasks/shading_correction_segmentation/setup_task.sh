#!/bin/bash
set -e
echo "=== Setting up Shading Correction task ==="

# 1. Create results directory and set permissions
mkdir -p /home/ga/Fiji_Data/results
mkdir -p /home/ga/Fiji_Data/raw
chown -R ga:ga /home/ga/Fiji_Data

# 2. Clean previous results
rm -f /home/ga/Fiji_Data/results/corrected_mask.png
rm -f /home/ga/Fiji_Data/results/particle_count.csv
rm -f /tmp/shading_result.json

# 3. Ensure blobs.gif is available (it's built-in, but we can also download/copy it to raw for convenience)
# We try to copy it from Fiji samples if available, or download it
if [ ! -f /home/ga/Fiji_Data/raw/blobs.gif ]; then
    echo "Downloading blobs.gif sample..."
    wget -q -O /home/ga/Fiji_Data/raw/blobs.gif https://imagej.nih.gov/ij/images/blobs.gif || \
    cp /opt/fiji/samples/blobs.gif /home/ga/Fiji_Data/raw/ 2>/dev/null || true
    chown ga:ga /home/ga/Fiji_Data/raw/blobs.gif 2>/dev/null || true
fi

# 4. Launch Fiji
echo "Launching Fiji..."
if [ -f /home/ga/launch_fiji.sh ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
else
    su - ga -c "DISPLAY=:1 fiji" &
fi

# 5. Wait for Fiji to be ready
echo "Waiting for Fiji window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null; then
        echo "Fiji detected."
        break
    fi
    sleep 1
done

# 6. Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="