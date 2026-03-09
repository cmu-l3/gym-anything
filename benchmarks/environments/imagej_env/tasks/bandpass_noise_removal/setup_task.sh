#!/bin/bash
set -e
echo "=== Setting up Bandpass Noise Removal task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/ImageJ_Data/raw
mkdir -p /home/ga/ImageJ_Data/results
mkdir -p /var/lib/imagej_ground_truth
chmod 700 /var/lib/imagej_ground_truth

# Clean previous results
rm -f /home/ga/ImageJ_Data/results/*

# Create the noisy image using Python
# We use the built-in 'blobs' sample (or download it) and add realistic noise
echo "Generating noisy microscopy data..."
python3 << 'PYEOF'
import numpy as np
from PIL import Image
import os
import urllib.request
import sys

# 1. Get the base image (Blobs sample)
img_path = "/tmp/blobs_base.gif"
url = "https://imagej.net/images/blobs.gif"

try:
    # Try to use local sample if available (from install script)
    local_sample = "/opt/imagej_samples/blobs.gif" 
    if os.path.exists(local_sample):
        print(f"Using local sample: {local_sample}")
        img = Image.open(local_sample).convert("L")
    else:
        print(f"Downloading sample from {url}...")
        urllib.request.urlretrieve(url, img_path)
        img = Image.open(img_path).convert("L")
except Exception as e:
    print(f"Failed to load standard sample: {e}")
    # Fallback: Generate synthetic data
    print("Generating synthetic data...")
    y, x = np.mgrid[0:256, 0:256]
    img_array = np.zeros((256, 256), dtype=np.float64)
    # Add blobs
    np.random.seed(42)
    for _ in range(15):
        cx, cy = np.random.randint(20, 236, 2)
        r = np.sqrt((x-cx)**2 + (y-cy)**2)
        img_array += 100 * np.exp(-r**2 / (2*15**2))
    img = Image.fromarray(np.clip(img_array, 0, 255).astype(np.uint8))

# Convert to numpy
clean_arr = np.array(img, dtype=np.float64)

# Save Clean Ground Truth (Hidden)
Image.fromarray(clean_arr.astype(np.uint8)).save("/var/lib/imagej_ground_truth/clean_reference.tif")

# 2. Add Noise
h, w = clean_arr.shape
np.random.seed(101) # Fixed seed for reproducibility

# A. Gaussian Noise (High Frequency)
noise_sigma = 25.0
gaussian_noise = np.random.normal(0, noise_sigma, (h, w))

# B. Background Gradient (Low Frequency) - Simulates uneven illumination
y_grid, x_grid = np.mgrid[0:h, 0:w]
# Diagonal gradient
gradient = 40.0 * (x_grid / w + y_grid / h - 1.0) 

# Combine
noisy_arr = clean_arr + gaussian_noise + gradient
noisy_arr = np.clip(noisy_arr, 0, 255).astype(np.uint8)

# Save Noisy Image for Agent
output_path = "/home/ga/ImageJ_Data/raw/noisy_blobs.tif"
Image.fromarray(noisy_arr).save(output_path)

print(f"Created noisy image at {output_path}")
print(f"Original stats: Mean={clean_arr.mean():.2f}, Std={clean_arr.std():.2f}")
print(f"Noisy stats: Mean={noisy_arr.mean():.2f}, Std={noisy_arr.std():.2f}")
PYEOF

# Set permissions
chown -R ga:ga /home/ga/ImageJ_Data

# Ensure Fiji is running
echo "Ensuring Fiji is running..."
kill_fiji
sleep 2

FIJI_PATH=$(find_fiji_executable)
if [ -n "$FIJI_PATH" ]; then
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /dev/null 2>&1 &"
    
    # Wait for Fiji
    wait_for_fiji 60
    
    # Maximize window
    WID=$(get_fiji_window_id)
    maximize_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="