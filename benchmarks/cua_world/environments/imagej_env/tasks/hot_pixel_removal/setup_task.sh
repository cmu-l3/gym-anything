#!/bin/bash
# Setup script for Hot Pixel Removal task
# Generates a synthetic 16-bit astronomical image with hot pixel noise

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up Hot Pixel Removal Task ==="

# Directories
DATA_DIR="/home/ga/ImageJ_Data/raw"
RESULTS_DIR="/home/ga/ImageJ_Data/results"
GT_DIR="/var/lib/imagej/ground_truth"

mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
mkdir -p "$GT_DIR"

chown -R ga:ga "/home/ga/ImageJ_Data"

# Clean up previous run
rm -f "$DATA_DIR/noisy_galaxy.tif"
rm -f "$RESULTS_DIR/clean_galaxy.tif"
rm -f "$GT_DIR/clean_galaxy_gt.tif"

# Record task start time
date +%s > /tmp/task_start_timestamp

# Generate synthetic astronomical data using Python
# We use Python to ensure we have a perfect ground truth and exact noise control
echo "Generating synthetic astronomical data..."

python3 << 'EOF'
import numpy as np
from PIL import Image
import os
import random

def create_galaxy_image(width, height):
    # Create black background with low sensor noise
    # 16-bit range is 0-65535
    data = np.random.normal(1000, 50, (height, width)).astype(np.float64)
    
    # Add a "Galaxy" (Large Gaussian blob)
    y, x = np.ogrid[:height, :width]
    center_y, center_x = height // 2, width // 2
    
    # Galaxy core
    mask = ((x - center_x)**2 + (y - center_y)**2)
    galaxy = 40000 * np.exp(-mask / (2 * (width/8)**2))
    data += galaxy
    
    # Add "Stars" (Small Gaussian spots)
    num_stars = 50
    for _ in range(num_stars):
        sy = random.randint(0, height-1)
        sx = random.randint(0, width-1)
        brightness = random.randint(10000, 50000)
        # Small point spread function
        star_mask = ((x - sx)**2 + (y - sy)**2)
        star = brightness * np.exp(-star_mask / 2.0)
        data += star

    # Clip to 16-bit range
    data = np.clip(data, 0, 65535).astype(np.uint16)
    return data

def add_hot_pixels(img_data, count):
    noisy = img_data.copy()
    height, width = noisy.shape
    for _ in range(count):
        y = random.randint(0, height-1)
        x = random.randint(0, width-1)
        noisy[y, x] = 65535 # Max 16-bit value
    return noisy

# Parameters
w, h = 512, 512
hot_pixel_count = 300

# Generate Ground Truth
clean_data = create_galaxy_image(w, h)
clean_img = Image.fromarray(clean_data)
clean_img.save("/var/lib/imagej/ground_truth/clean_galaxy_gt.tif")

# Generate Noisy Input
noisy_data = add_hot_pixels(clean_data, hot_pixel_count)
noisy_img = Image.fromarray(noisy_data)
noisy_img.save("/home/ga/ImageJ_Data/raw/noisy_galaxy.tif")

print(f"Generated images: {w}x{h}, {hot_pixel_count} hot pixels")
EOF

# Set permissions
chown ga:ga "$DATA_DIR/noisy_galaxy.tif"
chmod 644 "$DATA_DIR/noisy_galaxy.tif"
chmod 644 "$GT_DIR/clean_galaxy_gt.tif" # Readable for verification

# Ensure Fiji is not running
kill_fiji 2>/dev/null || true

# Start Fiji for the user
echo "Launching Fiji..."
launch_fiji
sleep 10

# Maximize and focus
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="