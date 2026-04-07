#!/bin/bash
echo "=== Setting up Detect and Count Stars Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create directories
WORK_DIR="/home/ga/AstroImages/star_detection"
MEASURE_DIR="/home/ga/AstroImages/measurements"

# Clean any previous artifacts
rm -rf "$WORK_DIR"
rm -rf "$MEASURE_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$MEASURE_DIR"

# Ensure real data exists and copy it
M12_SOURCE_DIR="/opt/fits_samples/m12"
VCOMB_FITS="$M12_SOURCE_DIR/Vcomb.fits"

if [ ! -f "$VCOMB_FITS" ]; then
    echo "Warning: Vcomb.fits not found at $M12_SOURCE_DIR. Attempting to download..."
    mkdir -p "$M12_SOURCE_DIR"
    wget -q --timeout=60 "https://esahubble.org/static/projects/fits_liberator/datasets/m12/Vcomb.zip" -O /tmp/Vcomb.zip
    if [ -f /tmp/Vcomb.zip ]; then
        cd "$M12_SOURCE_DIR" && unzip -o /tmp/Vcomb.zip
        rm -f /tmp/Vcomb.zip
    else
        echo "CRITICAL ERROR: Could not get M12 data."
        exit 1
    fi
fi

# Copy FITS to working directory
cp "$VCOMB_FITS" "$WORK_DIR/m12_Vcomb.fits"

# Optional reference catalog (for flavor, not strictly required for completion)
if [ -f "$M12_SOURCE_DIR/m12_B_V.xls" ]; then
    cp "$M12_SOURCE_DIR/m12_B_V.xls" "$WORK_DIR/m12_reference_catalog.xls"
fi

chown -R ga:ga "$WORK_DIR"
chown -R ga:ga "$MEASURE_DIR"

# Compute Ground Truth dynamically from the real FITS file
echo "Computing ground truth bounds from image..."
cat << 'EOF' > /tmp/compute_gt.py
import json
import os
import numpy as np
from astropy.io import fits
from scipy.ndimage import maximum_filter

fits_path = "/home/ga/AstroImages/star_detection/m12_Vcomb.fits"
gt = {
    "computed_star_count": 0,
    "bg_median": 0.0,
    "bg_std": 0.0,
    "error": None
}

try:
    if os.path.exists(fits_path):
        data = fits.getdata(fits_path).astype(float)
        # Handle 3D/empty dimensions
        if data.ndim == 3:
            data = data[0]
            
        bg_median = float(np.nanmedian(data))
        bg_std = float(np.nanstd(data))
        
        # Simple local maxima above 5-sigma
        local_max = maximum_filter(data, size=5) == data
        peaks = (data > (bg_median + 5 * bg_std)) & local_max
        star_count = int(np.sum(peaks))
        
        gt["computed_star_count"] = star_count
        gt["bg_median"] = bg_median
        gt["bg_std"] = bg_std
except Exception as e:
    gt["error"] = str(e)

with open("/tmp/m12_detection_ground_truth.json", "w") as f:
    json.dump(gt, f)
EOF

python3 /tmp/compute_gt.py

# Launch AstroImageJ (do not load the image, agent must do it)
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize and Focus AIJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="