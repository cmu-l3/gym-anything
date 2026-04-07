#!/bin/bash
set -e
echo "=== Setting up Multi-Channel Cell Pipeline task ==="

# 1. Create directory structure
DATA_DIR="/home/ga/Fiji_Data/raw/confocal"
RESULTS_DIR="/home/ga/Fiji_Data/results/cell_pipeline"

mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga /home/ga/Fiji_Data

# 2. Clean previous results (BEFORE recording timestamp per convention)
rm -f "$RESULTS_DIR"/* 2>/dev/null || true

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Download FluorescentCells image
# IMPORTANT: The .tif direct URL is known to 404 (returns 0-byte file).
# Must download the .zip archive and extract.
IMAGE_PATH="$DATA_DIR/FluorescentCells.tif"

if [ ! -f "$IMAGE_PATH" ] || [ "$(stat -c%s "$IMAGE_PATH" 2>/dev/null || echo 0)" -lt 100000 ]; then
    echo "Downloading FluorescentCells.zip..."
    rm -f /tmp/FluorescentCells.zip "$IMAGE_PATH" 2>/dev/null || true

    # Try multiple mirrors for the ZIP archive
    wget -q --timeout=60 "https://imagej.nih.gov/ij/images/FluorescentCells.zip" \
        -O /tmp/FluorescentCells.zip 2>/dev/null || \
    wget -q --timeout=60 "https://wsr.imagej.net/images/FluorescentCells.zip" \
        -O /tmp/FluorescentCells.zip 2>/dev/null || \
    true

    if [ -f /tmp/FluorescentCells.zip ] && \
       [ "$(stat -c%s /tmp/FluorescentCells.zip 2>/dev/null || echo 0)" -gt 100000 ]; then
        echo "Extracting FluorescentCells.tif from archive..."
        unzip -o -j /tmp/FluorescentCells.zip -d "$DATA_DIR/" 2>/dev/null || true
        rm -f /tmp/FluorescentCells.zip
    fi
fi

# 5. Validate the image file
# FluorescentCells.tif is 3 channels x 512x512, ~790KB
if [ -f "$IMAGE_PATH" ] && \
   [ "$(stat -c%s "$IMAGE_PATH" 2>/dev/null || echo 0)" -gt 100000 ]; then
    echo "FluorescentCells.tif ready ($(stat -c%s "$IMAGE_PATH") bytes)"
else
    echo "ERROR: FluorescentCells.tif not available or corrupted."
    echo "Download may have failed. Cannot proceed with task."
    exit 1
fi

# 6. Set permissions
chown -R ga:ga /home/ga/Fiji_Data

# 7. Launch Fiji (without pre-opening the image — agent must open it)
echo "Launching Fiji..."
pkill -f "fiji" 2>/dev/null || true
pkill -f "ImageJ" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /tmp/fiji_launch.log 2>&1 &

# 8. Wait for Fiji window
echo "Waiting for Fiji window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "ImageJ|Fiji"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

sleep 5

# 9. Maximize Fiji window
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 10. Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
