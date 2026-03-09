#!/bin/bash
set -e
echo "=== Setting up DNA Cell Cycle Analysis Task ==="

# Define directories
DATA_DIR="/home/ga/Fiji_Data/raw/cell_cycle"
RESULTS_DIR="/home/ga/Fiji_Data/results/cell_cycle"
mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"

# Clean up previous runs
rm -f "$RESULTS_DIR"/*
rm -f /tmp/task_result.json

# Record start time
date +%s > /tmp/task_start_time.txt

# Download Data (BBBC008 DAPI channel)
# We use a specific image known to have a good cell cycle distribution
IMAGE_URL="https://data.broadinstitute.org/bbbc/BBBC008/BBBC008_v1_images.zip"
TARGET_FILE="BBBC008_v1_A01_s1_w1.TIF"
LOCAL_FILE="$DATA_DIR/nuclei.tif"

if [ ! -f "$LOCAL_FILE" ]; then
    echo "Downloading dataset..."
    wget -q --timeout=120 "$IMAGE_URL" -O /tmp/bbbc008.zip || echo "Download failed"
    
    if [ -f /tmp/bbbc008.zip ]; then
        unzip -j /tmp/bbbc008.zip "*$TARGET_FILE" -d "$DATA_DIR/" 2>/dev/null || true
        mv "$DATA_DIR/$TARGET_FILE" "$LOCAL_FILE" 2>/dev/null || \
        mv "$DATA_DIR/"*"w1.TIF" "$LOCAL_FILE" 2>/dev/null || true
        rm /tmp/bbbc008.zip
    fi
fi

# Fallback if download failed
if [ ! -f "$LOCAL_FILE" ]; then
    echo "Using fallback image..."
    # Generate a synthetic image if real download fails to ensure task is playable
    python3 -c "
import numpy as np
from skimage import io, draw, filters, util
img = np.zeros((512, 512), dtype=np.uint16)
rng = np.random.default_rng(42)
# G1 cells (intensity ~20000)
for _ in range(30):
    r, c = rng.integers(20, 490, size=2)
    rr, cc = draw.disk((r, c), 10, shape=img.shape)
    img[rr, cc] = 20000 + rng.normal(0, 1000, size=len(rr))
# G2 cells (intensity ~40000)
for _ in range(10):
    r, c = rng.integers(20, 490, size=2)
    rr, cc = draw.disk((r, c), 13, shape=img.shape)
    img[rr, cc] = 40000 + rng.normal(0, 2000, size=len(rr))
# Add noise
noise = rng.normal(100, 10, img.shape)
img = np.clip(img + noise, 0, 65535).astype(np.uint16)
io.imsave('$LOCAL_FILE', img, check_contrast=False)
"
fi

chown -R ga:ga "/home/ga/Fiji_Data"

# ------------------------------------------------------------------
# CALCULATE GROUND TRUTH (Hidden from agent)
# We calculate the G1 peak using Python to verify the agent's result
# ------------------------------------------------------------------
echo "Calculating ground truth..."
python3 -c "
import numpy as np
from skimage import io, filters, measure, morphology, feature
from scipy import stats, ndimage
import json

try:
    # Load image
    img = io.imread('$LOCAL_FILE')
    
    # Simple background subtraction (top-hat) or just thresholding
    # Note: replicating exact Rolling Ball is hard in pure scipy, 
    # but Otsu is robust enough for the peak location usually.
    # We'll use a simple background subtraction approximation.
    bg = filters.gaussian(img, sigma=50)
    img_sub = img.astype(float) - bg
    img_sub = np.clip(img_sub, 0, None)
    
    # Threshold
    thresh = filters.threshold_otsu(img_sub)
    mask = img_sub > thresh
    
    # Watershed
    distance = ndimage.distance_transform_edt(mask)
    coords = feature.peak_local_max(distance, min_distance=7, labels=mask)
    mask_bool = np.zeros(distance.shape, dtype=bool)
    mask_bool[tuple(coords.T)] = True
    markers, _ = ndimage.label(mask_bool)
    labels = morphology.watershed(-distance, markers, mask=mask)
    
    # Measure properties
    props = measure.regionprops(labels, intensity_image=img_sub)
    
    # Get integrated densities
    # Area * MeanIntensity. Note: Fiji's RawIntDen is sum of pixel values.
    # img_sub is float, so we sum it.
    integrated_densities = [p.intensity_image.sum() for p in props if p.area > 50]
    
    if len(integrated_densities) > 5:
        # Find mode (peak) using Kernel Density Estimation
        kde = stats.gaussian_kde(integrated_densities)
        x_grid = np.linspace(min(integrated_densities), max(integrated_densities), 1000)
        y_grid = kde(x_grid)
        peak_val = x_grid[np.argmax(y_grid)]
        
        gt = {
            'g1_peak': float(peak_val),
            'cell_count': len(integrated_densities),
            'status': 'success'
        }
    else:
        gt = {'status': 'failed', 'reason': 'not enough cells'}

    with open('/var/lib/ground_truth.json', 'w') as f:
        json.dump(gt, f)

except Exception as e:
    with open('/var/lib/ground_truth.json', 'w') as f:
        json.dump({'status': 'error', 'reason': str(e)}, f)
"

# Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
sleep 10

# Maximize window
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Pre-load image
su - ga -c "DISPLAY=:1 /usr/local/bin/fiji -eval 'open(\"$LOCAL_FILE\");'" &

echo "=== Setup complete ==="