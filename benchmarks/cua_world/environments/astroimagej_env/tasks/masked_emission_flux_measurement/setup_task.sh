#!/bin/bash
echo "=== Setting up Masked Emission Flux Measurement Task ==="

source /workspace/scripts/task_utils.sh

# Define directories
WORK_DIR="/home/ga/AstroImages/emission_analysis"
OUT_DIR="$WORK_DIR/output"

# Clean up any previous state
rm -rf "$WORK_DIR"
mkdir -p "$OUT_DIR"

# Source file path
SOURCE_FITS="/opt/fits_samples/eagle_nebula/656nmos.fits"
TARGET_FITS="$WORK_DIR/656nmos.fits"

# Copy source file
if [ -f "$SOURCE_FITS" ]; then
    cp "$SOURCE_FITS" "$TARGET_FITS"
else
    echo "ERROR: Source FITS file not found at $SOURCE_FITS"
    exit 1
fi

chown -R ga:ga "$WORK_DIR"

# Calculate ground truth dynamically using Python
echo "Calculating ground truth from real data..."
python3 << 'PYEOF'
import json
import numpy as np
import os
from astropy.io import fits

file_path = "/home/ga/AstroImages/emission_analysis/656nmos.fits"

try:
    with fits.open(file_path) as hdul:
        data = hdul[0].data.astype(float)
        
    # Isolate valid (finite) pixels like ImageJ does
    valid_data = data[np.isfinite(data)]
    
    # Calculate statistics (using ddof=1 to match ImageJ sample stddev)
    mean_val = float(np.mean(valid_data))
    std_val = float(np.std(valid_data, ddof=1))
    
    # Calculate threshold
    threshold = mean_val + 3.0 * std_val
    
    # Generate mask
    mask = valid_data >= threshold
    
    # Calculate Area
    area_pixels = int(np.sum(mask))
    area_sq_arcsec = float(area_pixels * 0.01) # Plate scale is 0.1 arcsec/pix -> 0.01 sq arcsec/pix
    
    # Calculate masked mean
    masked_mean = float(np.mean(valid_data[mask]))
    
    gt = {
        "image_mean": mean_val,
        "image_stddev": std_val,
        "threshold_value": threshold,
        "area_pixels": area_pixels,
        "emission_area_sq_arcsec": area_sq_arcsec,
        "masked_mean_intensity": masked_mean
    }
    
    with open('/tmp/emission_ground_truth.json', 'w') as f:
        json.dump(gt, f, indent=2)
        
    print(f"Calculated GT: Mean={mean_val:.2f}, Std={std_val:.2f}, Threshold={threshold:.2f}, Area={area_sq_arcsec:.2f}, MaskedMean={masked_mean:.2f}")

except Exception as e:
    print(f"Error calculating ground truth: {e}")
    # Write empty JSON so verifier doesn't crash on read
    with open('/tmp/emission_ground_truth.json', 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

# Record start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Configure window for visibility
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="