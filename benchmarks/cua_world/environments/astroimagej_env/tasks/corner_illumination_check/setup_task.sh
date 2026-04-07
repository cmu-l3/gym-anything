#!/bin/bash
echo "=== Setting up Corner Illumination Uniformity task ==="

source /workspace/scripts/task_utils.sh

# Create clean working directory
WORK_DIR="/home/ga/AstroImages/uniformity_check"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure source data exists
SOURCE_FITS="/opt/fits_samples/m12/Vcomb.fits"
if [ ! -f "$SOURCE_FITS" ]; then
    echo "ERROR: Source data missing: $SOURCE_FITS"
    exit 1
fi

# Copy FITS to working directory
cp "$SOURCE_FITS" "$WORK_DIR/m12_Vcomb.fits"

# Use Python to compute ground truth from the ACTUAL pixel values
# and generate the ROI instruction file
python3 << 'PYEOF'
import os
import json
import numpy as np
from astropy.io import fits

fits_path = "/home/ga/AstroImages/uniformity_check/m12_Vcomb.fits"
instr_path = "/home/ga/AstroImages/uniformity_check/roi_instructions.txt"
gt_path = "/tmp/uniformity_ground_truth.json"

try:
    # Read image data
    data = fits.getdata(fits_path).astype(float)
    if data.ndim == 3:
        data = data[0]
    elif data.ndim > 3:
        data = data.reshape(-1, data.shape[-1])[:data.shape[-2], :]
    
    h, w = data.shape
    
    # ROI configuration
    size = 200
    off = 20
    
    # Write instructions for the agent
    with open(instr_path, 'w') as f:
        f.write(f"Image Dimensions: {w} x {h} pixels\n")
        f.write("Please place a 200x200 rectangular ROI at the following (X, Y) top-left coordinates:\n\n")
        f.write(f"Corner TL: X={off}, Y={off}\n")
        f.write(f"Corner TR: X={w - off - size}, Y={off}\n")
        f.write(f"Corner BL: X={off}, Y={h - off - size}\n")
        f.write(f"Corner BR: X={w - off - size}, Y={h - off - size}\n\n")
        f.write("Record the median and stddev for each region to generate your report.\n")
    
    # Compute Ground Truth
    regions = {
        "TL": data[off : off + size, off : off + size],
        "TR": data[off : off + size, w - off - size : w - off],
        "BL": data[h - off - size : h - off, off : off + size],
        "BR": data[h - off - size : h - off, w - off - size : w - off]
    }
    
    gt = {}
    medians = []
    for corner, region in regions.items():
        med = float(np.nanmedian(region))
        std = float(np.nanstd(region))
        gt[corner] = {"median": med, "stddev": std}
        medians.append(med)
        
    max_med = max(medians)
    min_med = min(medians)
    mean_med = sum(medians) / 4.0
    
    diff_pct = 100.0 * (max_med - min_med) / mean_med
    gt["max_diff_pct"] = diff_pct
    
    if diff_pct < 5.0:
        ass = "UNIFORM"
    elif diff_pct <= 10.0:
        ass = "MARGINAL"
    else:
        ass = "NON-UNIFORM"
        
    gt["assessment"] = ass
    
    with open(gt_path, 'w') as f:
        json.dump(gt, f, indent=2)
        
    print("Ground truth computed and instructions generated successfully.")
    
except Exception as e:
    print(f"Error computing ground truth: {e}")
PYEOF

chown -R ga:ga "$WORK_DIR"
chmod 644 "$WORK_DIR"/*

# Launch AstroImageJ (agent must load the image manually)
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize Window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="