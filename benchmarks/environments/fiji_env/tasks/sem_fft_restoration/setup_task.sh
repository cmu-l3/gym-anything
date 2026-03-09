#!/bin/bash
set -e
echo "=== Setting up SEM FFT Restoration Task ==="

# Define paths
DATA_DIR="/home/ga/Fiji_Data/raw/sem_noise"
RESULTS_DIR="/home/ga/Fiji_Data/results/sem_restoration"
GT_DIR="/var/lib/fiji/ground_truth"

# Create directories
mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
mkdir -p "$GT_DIR"

# Clean previous state
rm -f "$DATA_DIR/alloy_noisy.tif"
rm -f "$RESULTS_DIR/alloy_restored.tif"
rm -f "$GT_DIR/alloy_clean.tif"

# Record start time
date +%s > /tmp/task_start_time.txt

# Download base image (Eutectic Alloy Sample)
# Using the official ImageJ sample URL
BASE_URL="https://imagej.nih.gov/ij/images/AuPbSn40.jpg"
wget -q "$BASE_URL" -O /tmp/base_image.jpg || {
    echo "Failed to download base image, using fallback generation..."
    # Fallback handled in python script
}

# Generate Noisy Data and Ground Truth using Python
# We do this to ensure we have a perfect ground truth and known noise characteristics
echo "Generating noisy SEM image..."
python3 << 'PYEOF'
import numpy as np
from PIL import Image, ImageDraw
import os
import scipy.ndimage

# Config
width, height = 512, 512
base_image_path = "/tmp/base_image.jpg"
output_noisy = "/home/ga/Fiji_Data/raw/sem_noise/alloy_noisy.tif"
output_clean = "/var/lib/fiji/ground_truth/alloy_clean.tif"

try:
    # Load base image
    if os.path.exists(base_image_path):
        img = Image.open(base_image_path).convert('L')
        img = img.resize((width, height))
        arr = np.array(img).astype(float)
    else:
        # Synthetic structure if download failed
        print("Using synthetic structure")
        x, y = np.meshgrid(np.arange(width), np.arange(height))
        arr = np.sin(x/5.0) * np.cos(y/5.0) * 128 + 128
        
    # Normalize to 0-255
    arr = (arr - arr.min()) / (arr.max() - arr.min()) * 255.0
    
    # Save Clean Ground Truth
    Image.fromarray(arr.astype(np.uint8)).save(output_clean)
    
    # Add Periodic Noise
    # Diagonal sine wave
    x, y = np.meshgrid(np.arange(width), np.arange(height))
    # Frequency components
    fx, fy = 0.15, 0.15 
    noise = 40.0 * np.sin(2 * np.pi * (fx * x + fy * y))
    
    # Add noise
    noisy_arr = arr + noise
    noisy_arr = np.clip(noisy_arr, 0, 255)
    
    # Save Noisy Input
    Image.fromarray(noisy_arr.astype(np.uint8)).save(output_noisy)
    
    print(f"Generated images:\n GT: {output_clean}\n Input: {output_noisy}")
    
except Exception as e:
    print(f"Error generating data: {e}")
    exit(1)
PYEOF

# Set permissions
chown -R ga:ga "/home/ga/Fiji_Data"
chmod 755 "$GT_DIR" # Agent can read directory but maybe not file easily if they don't look
chmod 644 "$GT_DIR/alloy_clean.tif"

# Launch Fiji with the noisy image
echo "Launching Fiji..."
if pgrep -f "fiji" > /dev/null; then
    pkill -f "fiji"
    sleep 2
fi

# Use the launch script if available, otherwise direct
LAUNCH_CMD="/home/ga/launch_fiji.sh"
if [ ! -f "$LAUNCH_CMD" ]; then
    LAUNCH_CMD="/opt/fiji/Fiji.app/ImageJ-linux64"
fi

# Launch in background as user ga
su - ga -c "DISPLAY=:1 $LAUNCH_CMD /home/ga/Fiji_Data/raw/sem_noise/alloy_noisy.tif" &

# Wait for window
echo "Waiting for Fiji window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ" > /dev/null; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "alloy_noisy.tif" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="