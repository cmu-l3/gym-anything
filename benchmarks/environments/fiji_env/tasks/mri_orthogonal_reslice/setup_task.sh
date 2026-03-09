#!/bin/bash
set -e
echo "=== Setting up MRI Orthogonal Reslice Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Create directories
mkdir -p /home/ga/Fiji_Data/raw/t1-head
mkdir -p /home/ga/Fiji_Data/results/reslice
chown -R ga:ga /home/ga/Fiji_Data

# 3. Clean up previous results
rm -f /home/ga/Fiji_Data/results/reslice/*

# 4. Prepare the T1 Head dataset
# We download the raw zip, extract it, and convert raw to TIFF to ensure
# the agent starts with an uncalibrated TIFF as specified.
if [ ! -f "/home/ga/Fiji_Data/raw/t1-head/t1-head.tif" ]; then
    echo "Downloading and preparing T1 Head data..."
    
    cd /tmp
    wget -q "https://imagej.net/ij/images/t1-head-raw.zip" -O t1-head-raw.zip
    unzip -q t1-head-raw.zip
    
    # Use Python to convert raw (256x256x129, 16-bit big-endian) to TIFF
    # We purposefully do NOT set resolution metadata here, as the task requires the agent to do it.
    python3 -c "
import numpy as np
from PIL import Image
import os

# Read raw file (16-bit big-endian)
raw_path = 't1-head.raw'
if os.path.exists(raw_path):
    # 256 * 256 * 129 * 2 bytes
    data = np.fromfile(raw_path, dtype='>u2') 
    data = data.reshape((129, 256, 256))
    
    # Save as multi-page TIFF
    imgs = [Image.fromarray(data[i]) for i in range(129)]
    imgs[0].save('/home/ga/Fiji_Data/raw/t1-head/t1-head.tif', save_all=True, append_images=imgs[1:])
    print('Converted raw to uncalibrated TIFF.')
else:
    print('Error: t1-head.raw not found')
"
    rm -f t1-head.raw t1-head-raw.zip
    chown ga:ga /home/ga/Fiji_Data/raw/t1-head/t1-head.tif
fi

# 5. Launch Fiji
echo "Launching Fiji..."
if ! pgrep -f "fiji" > /dev/null && ! pgrep -f "ImageJ" > /dev/null; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
    sleep 10
fi

# 6. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ"; then
        echo "Fiji window detected."
        DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
        DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 7. Open the image for the agent (optional convenience, but good for starting state)
# We use xdotool to open the file via the menu or command line if possible.
# Simpler: Just rely on agent to open it, but let's pre-load it for better UX if possible.
# Actually, the task desc says "Open the image...". We will leave it to the agent or 
# we can use the 'fiji <file>' command. Let's restart fiji with the file to be helpful.
pkill -f "fiji" || true
pkill -f "ImageJ" || true
sleep 2
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh /home/ga/Fiji_Data/raw/t1-head/t1-head.tif" &
sleep 10

# Maximize again
DISPLAY=:1 wmctrl -r "t1-head.tif" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="