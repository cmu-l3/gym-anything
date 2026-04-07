#!/bin/bash
echo "=== Setting up Galaxy Isophotal Morphology Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
date +%s > /tmp/task_start_time

# Prepare directories
RAW_DIR="/home/ga/AstroImages/raw"
MEASURE_DIR="/home/ga/AstroImages/measurements"
mkdir -p "$RAW_DIR" "$MEASURE_DIR"

# Ensure FITS file exists
FITS_SRC="/opt/fits_samples/uit_galaxy_sample.fits"
FITS_DEST="$RAW_DIR/uit_galaxy_sample.fits"

if [ -f "$FITS_SRC" ]; then
    cp "$FITS_SRC" "$FITS_DEST"
else
    # Fallback download if missing from env setup
    echo "Downloading UIT galaxy sample..."
    wget -q --timeout=30 "https://fits.gsfc.nasa.gov/samples/UITfuv2582gc.fits" -O "$FITS_DEST"
fi

# Clean up any prior task artifacts
rm -f "$MEASURE_DIR/galaxy_morphology.csv" 2>/dev/null || true
rm -f "$MEASURE_DIR/morphology_report.txt" 2>/dev/null || true
rm -f /tmp/galaxy_gt.json 2>/dev/null || true

# ============================================================
# Compute dynamic ground truth using python
# This perfectly mimics what ImageJ will measure for the region
# ============================================================
python3 << 'PYEOF'
import json
import numpy as np
from astropy.io import fits
from scipy import ndimage

FITS_PATH = "/home/ga/AstroImages/raw/uit_galaxy_sample.fits"

try:
    data = fits.getdata(FITS_PATH).astype(float)
    if data.ndim > 2:
        data = data[0]
        
    # Agent is instructed to use X=10, Y=10, W=50, H=50
    # In numpy, this corresponds to [Y:Y+H, X:X+W] -> [10:60, 10:60]
    bg_region = data[10:60, 10:60]
    
    mu = float(np.mean(bg_region))
    # ImageJ uses n-1 degrees of freedom for standard deviation
    sigma = float(np.std(bg_region, ddof=1))
    threshold = mu + (3.0 * sigma)
    
    # Apply threshold and find the main galaxy
    binary = data > threshold
    labeled, num_features = ndimage.label(binary)
    
    major, minor = 0.0, 0.0
    
    if num_features > 0:
        # Find largest component
        sizes = ndimage.sum(binary, labeled, range(1, num_features + 1))
        largest_idx = np.argmax(sizes) + 1
        y, x = np.nonzero(labeled == largest_idx)
        
        # Calculate ImageJ-equivalent spatial moments for ellipse fit
        m00 = len(x)
        if m00 > 0:
            x_bar = np.mean(x)
            y_bar = np.mean(y)
            u20 = np.sum((x - x_bar)**2) / m00
            u02 = np.sum((y - y_bar)**2) / m00
            u11 = np.sum((x - x_bar) * (y - y_bar)) / m00
            
            diff = u20 - u02
            rad = np.sqrt(diff**2 + 4 * u11**2)
            
            # Major and minor axes lengths matching ImageJ's algorithm
            major = 2.0 * np.sqrt(2.0) * np.sqrt(u20 + u02 + rad)
            minor = 2.0 * np.sqrt(2.0) * np.sqrt(u20 + u02 - rad)

    ellipticity = 1.0 - (minor / major) if major > 0 else 0.0
    
    gt = {
        "bg_mean": mu,
        "bg_std": sigma,
        "threshold": threshold,
        "major": major,
        "minor": minor,
        "ellipticity": ellipticity
    }
    
    with open('/tmp/galaxy_gt.json', 'w') as f:
        json.dump(gt, f)
    print("Ground truth computed successfully")
        
except Exception as e:
    print(f"Error computing ground truth: {e}")
PYEOF

chown -R ga:ga /home/ga/AstroImages

# ============================================================
# Launch AstroImageJ (Without loading the image)
# ============================================================
echo "Launching AstroImageJ..."
launch_astroimagej 60
sleep 2

# Maximize Window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="