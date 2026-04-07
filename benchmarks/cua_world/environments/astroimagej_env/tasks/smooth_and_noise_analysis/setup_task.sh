#!/bin/bash
echo "=== Setting up Gaussian Smoothing and Noise Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create working directories
WORK_DIR="/home/ga/AstroImages/eagle_smoothing"
OUTPUT_DIR="$WORK_DIR/output"
rm -rf "$WORK_DIR"
mkdir -p "$OUTPUT_DIR"

# Ensure source FITS file exists (downloaded during env build)
SOURCE_FITS="/opt/fits_samples/eagle_nebula/656nmos.fits"
if [ ! -f "$SOURCE_FITS" ]; then
    echo "ERROR: Source FITS file not found at $SOURCE_FITS"
    echo "Attempting to download fallback..."
    mkdir -p /opt/fits_samples/eagle_nebula/
    wget -q --timeout=60 "https://esahubble.org/static/projects/fits_liberator/datasets/eagle/656nmos.zip" -O /tmp/eagle.zip
    unzip -o /tmp/eagle.zip -d /opt/fits_samples/eagle_nebula/
    rm /tmp/eagle.zip
fi

# Copy FITS to working directory
TARGET_FITS="$WORK_DIR/656nmos.fits"
cp "$SOURCE_FITS" "$TARGET_FITS"

# Compute ground truth using Python (astropy + scipy)
python3 << 'PYEOF'
import json
import numpy as np
from astropy.io import fits
from scipy.ndimage import gaussian_filter

target_fits = "/home/ga/AstroImages/eagle_smoothing/656nmos.fits"

try:
    with fits.open(target_fits) as hdul:
        data = hdul[0].data.astype(float)
        
    # Original stats
    orig_mean = float(np.nanmean(data))
    orig_std = float(np.nanstd(data))
    
    # Smoothed stats (Sigma=3.0)
    smoothed = gaussian_filter(data, sigma=3.0, mode='nearest')
    smooth_mean = float(np.nanmean(smoothed))
    smooth_std = float(np.nanstd(smoothed))
    
    # Residual stats
    residual = data - smoothed
    resid_mean = float(np.nanmean(residual))
    resid_std = float(np.nanstd(residual))
    
    # Ground truth dict
    gt = {
        "orig_mean": orig_mean,
        "orig_std": orig_std,
        "smooth_mean": smooth_mean,
        "smooth_std": smooth_std,
        "resid_mean": resid_mean,
        "resid_std": resid_std,
        "noise_reduction_factor": float(orig_std / smooth_std) if smooth_std > 0 else 0,
        "shape": list(data.shape)
    }
    
    with open("/tmp/smoothing_ground_truth.json", "w") as f:
        json.dump(gt, f, indent=2)
        
    print(f"Ground truth computed successfully:")
    print(f"  Orig Mean: {orig_mean:.2f}, Std: {orig_std:.2f}")
    print(f"  Smooth Mean: {smooth_mean:.2f}, Std: {smooth_std:.2f}")
    print(f"  Residual Mean: {resid_mean:.2f}, Std: {resid_std:.2f}")
    print(f"  Noise Reduction Factor: {gt['noise_reduction_factor']:.2f}")

except Exception as e:
    print(f"Error computing ground truth: {e}")
PYEOF

chown -R ga:ga "$WORK_DIR"

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize AstroImageJ window
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="