#!/bin/bash
set -e
echo "=== Setting up Local Thickness Phase Mapping task ==="

# 1. timestamp setup
date +%s > /tmp/task_start_time.txt

# 2. Create directories
mkdir -p /home/ga/Fiji_Data/raw/metallography
mkdir -p /home/ga/Fiji_Data/results/thickness
chown -R ga:ga /home/ga/Fiji_Data

# 3. Clean previous results
rm -f /home/ga/Fiji_Data/results/thickness/*

# 4. Download and Prepare Real Data
# Using the classic AuPbSn40 ImageJ sample image
IMG_URL="https://imagej.nih.gov/ij/images/AuPbSn40.jpg"
DEST_JPG="/tmp/AuPbSn40.jpg"
FINAL_TIF="/home/ga/Fiji_Data/raw/metallography/AuPbSn40_alloy.tif"

echo "Downloading metallographic sample..."
if ! wget -q --timeout=30 "$IMG_URL" -O "$DEST_JPG"; then
    # Mirror fallback
    wget -q --timeout=30 "https://wsr.imagej.net/images/AuPbSn40.jpg" -O "$DEST_JPG" || {
        echo "ERROR: Failed to download sample image."
        exit 1
    }
fi

# Convert to TIFF for the task (preserves metadata better in Fiji workflows)
python3 -c "
from PIL import Image
try:
    img = Image.open('$DEST_JPG')
    img.save('$FINAL_TIF', format='TIFF')
    print(f'Converted to TIFF: {img.size}')
except Exception as e:
    print(f'Conversion failed: {e}')
    exit(1)
"

rm -f "$DEST_JPG"
chown ga:ga "$FINAL_TIF"

# 5. Launch Fiji
echo "Launching Fiji..."
pkill -f "fiji" || true
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize
sleep 2
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="