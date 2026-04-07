#!/bin/bash
set -euo pipefail
echo "=== Setting up M12 Cluster Core Extraction Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AstroImages/cluster_extraction"
OUTPUT_DIR="$PROJECT_DIR/output"
rm -rf "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"

# Ensure astropy and scipy are installed
pip3 install --no-cache-dir astropy scipy numpy >/dev/null 2>&1 || true

# Prepare data and generate ground truth dynamically
echo "Processing FITS image and finding cluster core..."
python3 << 'PYEOF'
import os, json
from astropy.io import fits
import numpy as np
from scipy.ndimage import uniform_filter

src = "/opt/fits_samples/m12/Vcomb.fits"
dst = "/home/ga/AstroImages/cluster_extraction/m12_vband.fits"

# Copy the file
os.system(f"cp {src} {dst}")

# Analyze the image to find the cluster core dynamically
try:
    data = fits.getdata(dst).astype(float)
    
    # Handle any potential NaNs in real observational data
    med_val = np.nanmedian(data)
    data = np.nan_to_num(data, nan=med_val)

    full_mean = float(np.mean(data))
    full_std = float(np.std(data))
    full_min = float(np.min(data))
    full_max = float(np.max(data))
    h, w = data.shape

    # Find cluster core (brightest 300x300 region)
    # uniform_filter computes the local mean in a moving window
    filtered = uniform_filter(data, size=300)
    cy, cx = np.unravel_index(np.argmax(filtered), filtered.shape)

    # Calculate exact 300x300 boundaries avoiding image edges
    y0 = max(0, int(cy - 150))
    y1 = min(h, y0 + 300)
    if y1 - y0 < 300: y0 = max(0, y1 - 300)

    x0 = max(0, int(cx - 150))
    x1 = min(w, x0 + 300)
    if x1 - x0 < 300: x0 = max(0, x1 - 300)

    subframe = data[y0:y1, x0:x1]
    sub_mean = float(np.mean(subframe))
    sub_std = float(np.std(subframe))
    sub_min = float(np.min(subframe))
    sub_max = float(np.max(subframe))

    gt = {
        "full_shape": [h, w],
        "full_mean": full_mean,
        "full_std": full_std,
        "full_min": full_min,
        "full_max": full_max,
        "center_x": int(cx),
        "center_y": int(cy),
        "sub_shape": [subframe.shape[0], subframe.shape[1]],
        "sub_mean": sub_mean,
        "sub_std": sub_std,
        "sub_min": sub_min,
        "sub_max": sub_max
    }

    # Save ground truth (hidden from agent)
    with open("/tmp/extraction_ground_truth.json", "w") as f:
        json.dump(gt, f)

    # Write target file for agent
    target_text = f"""# M12 Cluster Core Extraction Target
# Determined from peak brightness region of VLT V-band mosaic
CENTER_X = {int(cx)}
CENTER_Y = {int(cy)}
BOX_SIZE = 300

# INSTRUCTIONS:
# 1. Open m12_vband.fits
# 2. Extract a 300x300 pixel box centered on (CENTER_X, CENTER_Y)
# 3. Save the subframe to output/m12_core_subframe.fits
"""
    with open("/home/ga/AstroImages/cluster_extraction/extraction_target.txt", "w") as f:
        f.write(target_text)

except Exception as e:
    print(f"Error preparing data: {e}")
PYEOF

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Start AstroImageJ cleanly
echo "Launching AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
launch_astroimagej 60

# Maximize and focus AstroImageJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot showing clean state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="