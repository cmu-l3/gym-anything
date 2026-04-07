#!/bin/bash
echo "=== Setting up Measure Extended Galaxy Flux Task ==="

source /workspace/scripts/task_utils.sh

# Setup directories
RAW_DIR="/home/ga/AstroImages/raw"
MEASUREMENTS_DIR="/home/ga/AstroImages/measurements"
mkdir -p "$RAW_DIR" "$MEASUREMENTS_DIR"
chown -R ga:ga /home/ga/AstroImages

# Clean up any pre-existing files
rm -f "$MEASUREMENTS_DIR/roi_measurements.csv" 2>/dev/null || true
rm -f "$MEASUREMENTS_DIR/flux_report.txt" 2>/dev/null || true
rm -f /tmp/task_result.json /tmp/galaxy_flux_ground_truth.json 2>/dev/null || true

# Check for UIT sample image; copy if not in RAW_DIR
UIT_FITS="/opt/fits_samples/uit_galaxy_sample.fits"
TARGET_FITS="$RAW_DIR/uit_galaxy_sample.fits"

if [ -f "$UIT_FITS" ]; then
    cp "$UIT_FITS" "$TARGET_FITS"
    chown ga:ga "$TARGET_FITS"
else
    echo "ERROR: Could not find UIT sample image at $UIT_FITS"
    exit 1
fi

# ============================================================
# Compute Dynamic Ground Truth
# ============================================================
echo "Computing ground truth for the central galaxy..."
python3 << 'PYEOF'
import os
import json
import numpy as np
from astropy.io import fits
from scipy import ndimage

target_file = "/home/ga/AstroImages/raw/uit_galaxy_sample.fits"

try:
    with fits.open(target_file) as hdul:
        data = hdul[0].data.astype(float)
        
    # Handle NaN values
    data = np.nan_to_num(data, nan=np.nanmedian(data))
    
    # Estimate background from corner
    corner_pixels = data[:40, :40]
    bg_mean = float(np.median(corner_pixels))
    bg_std = float(np.std(corner_pixels))
    
    # Use Gaussian smoothing to isolate the central galaxy structure
    smoothed = ndimage.gaussian_filter(data, sigma=3.0)
    
    # Threshold to find main galaxy blob
    threshold = bg_mean + 4 * bg_std
    binary_mask = smoothed > threshold
    
    # Label regions
    labeled, num_features = ndimage.label(binary_mask)
    
    # Find the largest region (should be the central galaxy)
    if num_features > 0:
        sizes = ndimage.sum(binary_mask, labeled, range(num_features + 1))
        largest_label = np.argmax(sizes[1:]) + 1
        galaxy_mask = (labeled == largest_label)
        
        # Calculate ground truth statistics
        gt_area = int(np.sum(galaxy_mask))
        gt_intden = float(np.sum(data[galaxy_mask]))
        gt_net_flux = gt_intden - (bg_mean * gt_area)
    else:
        gt_area = 0
        gt_intden = 0.0
        gt_net_flux = 0.0
        
    ground_truth = {
        "gt_area": gt_area,
        "gt_int_den": gt_intden,
        "gt_bg_mean": bg_mean,
        "gt_net_flux": gt_net_flux,
        "image_shape": list(data.shape)
    }
    
    with open('/tmp/galaxy_flux_ground_truth.json', 'w') as f:
        json.dump(ground_truth, f, indent=2)
        
    print(f"Ground Truth Computed:")
    print(f"  Area: {gt_area} pixels")
    print(f"  IntDen: {gt_intden:.1f}")
    print(f"  Bg Mean: {bg_mean:.2f}")
    print(f"  Net Flux: {gt_net_flux:.1f}")

except Exception as e:
    print(f"Failed to compute ground truth: {e}")
PYEOF

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# ============================================================
# Launch AstroImageJ
# ============================================================
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize the window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="