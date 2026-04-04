#!/bin/bash
set -e
echo "=== Setting up SEM Phase Analysis task ==="

# 1. Create directory structure
mkdir -p /home/ga/Fiji_Data/results/sem_analysis
mkdir -p /home/ga/Fiji_Data/raw/sem
chown -R ga:ga /home/ga/Fiji_Data

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Clean previous results
rm -f /home/ga/Fiji_Data/results/sem_analysis/* 2>/dev/null || true

# 4. Prepare the image (AuPbSn40)
# We download the JPG and convert to TIF to ensure a clean slate (8-bit)
SEM_IMG="/home/ga/Fiji_Data/raw/sem/AuPbSn40.tif"

if [ ! -f "$SEM_IMG" ]; then
    echo "Downloading AuPbSn40 sample..."
    # Try multiple mirrors
    wget -q --timeout=30 "https://imagej.nih.gov/ij/images/AuPbSn40.jpg" -O /tmp/AuPbSn40.jpg 2>/dev/null || \
    wget -q --timeout=30 "https://wsr.imagej.net/images/AuPbSn40.jpg" -O /tmp/AuPbSn40.jpg 2>/dev/null || \
    wget -q --timeout=30 "https://imagej.net/images/AuPbSn40.jpg" -O /tmp/AuPbSn40.jpg

    if [ -f /tmp/AuPbSn40.jpg ]; then
        echo "Converting to TIFF..."
        python3 -c "
from PIL import Image
try:
    img = Image.open('/tmp/AuPbSn40.jpg').convert('L')
    img.save('$SEM_IMG')
    print('Converted to 8-bit TIFF')
except Exception as e:
    print(f'Error: {e}')
"
        rm -f /tmp/AuPbSn40.jpg
    else
        echo "ERROR: Failed to download AuPbSn40 sample image."
        exit 1
    fi
fi

# 5. Create scale info file for the agent
cat > /home/ga/Fiji_Data/raw/sem/scale_info.txt << 'EOF'
=== SEM Image Calibration Info ===
Image: AuPbSn40.tif
Instrument: SEM, Backscatter Electron (BSE) detector
Alloy: Au-Pb-Sn eutectic solder (~40 wt% Sn)

Spatial Calibration:
  Pixel width:  0.49 µm
  Pixel height: 0.49 µm
  Unit: µm

BSE Contrast Key:
  Bright  → Gold-rich intermetallic (high Z)
  Medium  → Lead-rich eutectic (medium Z)
  Dark    → Tin-rich dendrites (low Z)
EOF

chown -R ga:ga /home/ga/Fiji_Data/raw/sem

# 6. Launch Fiji with the image loaded
echo "Launching Fiji..."
pkill -f "fiji" 2>/dev/null || true
pkill -f "ImageJ" 2>/dev/null || true
sleep 1

# Launch as user ga
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh '$SEM_IMG'" > /tmp/fiji_launch.log 2>&1 &

# 7. Wait for window
echo "Waiting for Fiji window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "ImageJ|Fiji|AuPbSn"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

sleep 5

# 8. Maximize window
DISPLAY=:1 wmctrl -r "AuPbSn40" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="