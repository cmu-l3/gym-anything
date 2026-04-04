#!/bin/bash
set -e
echo "=== Setting up Galaxy Cluster Segmentation Task ==="

# 1. Create Directories
mkdir -p /home/ga/Fiji_Data/raw/astronomy/
mkdir -p /home/ga/Fiji_Data/results/astronomy/
chown -R ga:ga /home/ga/Fiji_Data

# 2. Download M51 Image (Real Data)
echo "Downloading M51 galaxy image..."
M51_URL="https://imagej.nih.gov/ij/images/m51.tif"
TARGET_FILE="/home/ga/Fiji_Data/raw/astronomy/m51.tif"

# Try primary URL, then mirror, then fallback to creating a dummy if absolutely necessary (but real data preferred)
wget -q "$M51_URL" -O "$TARGET_FILE" || \
wget -q "https://wsr.imagej.net/images/m51.tif" -O "$TARGET_FILE" || \
{ echo "Error: Could not download M51 image"; exit 1; }

# Ensure correct permissions
chown ga:ga "$TARGET_FILE"

# 3. Clean previous results
rm -f /home/ga/Fiji_Data/results/astronomy/*

# 4. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch Fiji
echo "Launching Fiji..."
if [ -f "/home/ga/launch_fiji.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
else
    su - ga -c "DISPLAY=:1 fiji" &
fi

# 6. Wait for Fiji Window
echo "Waiting for Fiji..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done
sleep 5

# 7. Maximize Window
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="