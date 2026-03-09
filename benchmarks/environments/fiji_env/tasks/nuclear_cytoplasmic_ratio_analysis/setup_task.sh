#!/bin/bash
set -e
echo "=== Setting up Nuclear-Cytoplasmic Ratio Analysis Task ==="

# 1. Prepare Directories
DATA_DIR="/home/ga/Fiji_Data/raw/translocation"
RESULTS_DIR="/home/ga/Fiji_Data/results/translocation"

mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"

# Ensure clean state
rm -f "$RESULTS_DIR/ratio_report.txt"
rm -f "$RESULTS_DIR/rois.zip"

# 2. Prepare Data (Download BBBC007 sample)
# We will use a specific image pair known to have good separation
# BBBC007 v1 images: Drosophila Kc167 cells
echo "Preparing image data..."

# Temporary download location
TEMP_DL="/tmp/bbbc007_sample"
mkdir -p "$TEMP_DL"

# Download a specific well (A01_s1) which usually has cells
# URLs from Broad Bioimage Benchmark Collection
DAPI_URL="https://data.broadinstitute.org/bbbc/BBBC007/BBBC007_v1_images/A01_s1_w127027521798F81395E095D4A32514AE.tif"
SIGNAL_URL="https://data.broadinstitute.org/bbbc/BBBC007/BBBC007_v1_images/A01_s1_w205C895744F76939C025095318536284.tif"

# Download if not cached
if [ ! -f "$DATA_DIR/cell_dapi.tif" ]; then
    echo "Downloading sample images..."
    # We use curl with fail to catch errors
    curl -L -f -o "$DATA_DIR/cell_dapi.tif" "$DAPI_URL" || \
        echo "Failed to download DAPI image"
    
    curl -L -f -o "$DATA_DIR/cell_signal.tif" "$SIGNAL_URL" || \
        echo "Failed to download Signal image"
fi

# Fallback: Generate synthetic data if download fails (Critical for offline robustness)
if [ ! -f "$DATA_DIR/cell_dapi.tif" ] || [ ! -s "$DATA_DIR/cell_dapi.tif" ]; then
    echo "WARNING: Download failed. Generating synthetic single-cell data..."
    python3 -c "
import numpy as np
from PIL import Image, ImageDraw
import os

# Create DAPI (Nucleus)
dapi = np.zeros((512, 512), dtype=np.uint8)
# Draw nucleus
img_d = Image.fromarray(dapi)
draw_d = ImageDraw.Draw(img_d)
draw_d.ellipse([200, 200, 300, 300], fill=200) # Bright nucleus
dapi = np.array(img_d)
# Add noise
dapi = dapi + np.random.normal(0, 5, dapi.shape).astype(np.uint8)
Image.fromarray(dapi).save('$DATA_DIR/cell_dapi.tif')

# Create Signal (Translocation)
signal = np.zeros((512, 512), dtype=np.uint8)
img_s = Image.fromarray(signal)
draw_s = ImageDraw.Draw(img_s)
# Nucleus signal (medium)
draw_s.ellipse([200, 200, 300, 300], fill=100)
# Cytoplasm signal (bright ring)
draw_s.ellipse([150, 150, 350, 350], fill=180) # Outer
draw_s.ellipse([200, 200, 300, 300], fill=100) # Inner (overwrite)
signal = np.array(img_s)
signal = signal + np.random.normal(0, 5, signal.shape).astype(np.uint8)
Image.fromarray(signal).save('$DATA_DIR/cell_signal.tif')
"
fi

# Set permissions
chown -R ga:ga "/home/ga/Fiji_Data"

# 3. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Launch Fiji
echo "Launching Fiji..."
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
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="