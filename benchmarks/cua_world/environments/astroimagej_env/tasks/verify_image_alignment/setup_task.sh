#!/bin/bash
# Setup script for Multi-Filter Alignment Verification task
# Uses real VLT Messier 12 observations

set -euo pipefail

echo "=== Setting up Alignment Verification Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Create working directories
WORK_DIR="/home/ga/AstroImages/alignment_check"
MEASUREMENTS_DIR="/home/ga/AstroImages/measurements"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$MEASUREMENTS_DIR"

# Source data directory (installed via environment setup)
M12_DIR="/opt/fits_samples/m12"

# Unzip FITS if needed
if ls "$M12_DIR"/*.zip 1> /dev/null 2>&1; then
    echo "Unzipping M12 archives..."
    unzip -q -o "$M12_DIR/Vcomb.zip" -d "$M12_DIR" 2>/dev/null || true
    unzip -q -o "$M12_DIR/Bcomb.zip" -d "$M12_DIR" 2>/dev/null || true
fi

# Ensure FITS files exist
if [ ! -f "$M12_DIR/Vcomb.fits" ] || [ ! -f "$M12_DIR/Bcomb.fits" ]; then
    echo "ERROR: Required FITS files not found in $M12_DIR"
    exit 1
fi

# Copy FITS files to working directory
cp "$M12_DIR/Vcomb.fits" "$WORK_DIR/"
cp "$M12_DIR/Bcomb.fits" "$WORK_DIR/"

# Create instructions file
cat > "$WORK_DIR/instructions.txt" << 'EOF'
Alignment Verification Task:
1. Measure centroids of >=5 stars in Vcomb.fits
2. Measure centroids of the same stars in Bcomb.fits
3. Calculate ΔX, ΔY, RMS, Max offset
4. Write report to ~/AstroImages/measurements/alignment_report.txt

Required Format:
Number of stars measured: <N>
Mean X offset (pixels): <value>
Mean Y offset (pixels): <value>
RMS offset (pixels): <value>
Max offset (pixels): <value>
Assessment: <aligned or misaligned>  (aligned if RMS < 1.5)
EOF

chown -R ga:ga "$WORK_DIR"
chown -R ga:ga "$MEASUREMENTS_DIR"

# ==============================================================================
# Compute Ground Truth dynamically from the actual FITS files
# ==============================================================================
echo "Computing ground truth alignment offsets..."

python3 << 'PYEOF'
import json
import os
import numpy as np
import math
from astropy.io import fits
from scipy.ndimage import maximum_filter, center_of_mass

work_dir = "/home/ga/AstroImages/alignment_check"
v_path = os.path.join(work_dir, "Vcomb.fits")
b_path = os.path.join(work_dir, "Bcomb.fits")

v_data = fits.getdata(v_path).astype(float)
b_data = fits.getdata(b_path).astype(float)

# Basic background subtraction
v_bg = np.nanmedian(v_data)
b_bg = np.nanmedian(b_data)
v_sub = v_data - v_bg

# Find peaks (bright stars)
threshold = np.nanpercentile(v_sub, 99.8)
local_max = maximum_filter(v_sub, size=15) == v_sub
peaks = local_max & (v_sub > threshold)
y_idx, x_idx = np.where(peaks)

# Sort by brightness
fluxes = v_sub[y_idx, x_idx]
sorted_indices = np.argsort(fluxes)[::-1]
y_idx, x_idx = y_idx[sorted_indices], x_idx[sorted_indices]

# Take top 30 stars to compute robust stats
y_idx = y_idx[:30]
x_idx = x_idx[:30]

dx_list = []
dy_list = []

w = 6  # window size for centroiding
for x, y in zip(x_idx, y_idx):
    if x < w or y < w or x > v_data.shape[1]-w-1 or y > v_data.shape[0]-w-1:
        continue

    # V centroid
    v_cut = v_data[y-w:y+w+1, x-w:x+w+1] - v_bg
    v_cut[v_cut < 0] = 0
    if np.sum(v_cut) <= 0: continue
    cy_v, cx_v = center_of_mass(v_cut)
    abs_cx_v = x - w + cx_v
    abs_cy_v = y - w + cy_v

    # B centroid
    b_cut = b_data[y-w:y+w+1, x-w:x+w+1] - b_bg
    b_cut[b_cut < 0] = 0
    if np.sum(b_cut) <= 0: continue
    cy_b, cx_b = center_of_mass(b_cut)
    abs_cx_b = x - w + cx_b
    abs_cy_b = y - w + cy_b

    dx = abs_cx_b - abs_cx_v
    dy = abs_cy_b - abs_cy_v
    
    # Filter out wild mis-matches
    if abs(dx) < 5.0 and abs(dy) < 5.0:
        dx_list.append(dx)
        dy_list.append(dy)

if len(dx_list) > 0:
    mean_dx = float(np.mean(dx_list))
    mean_dy = float(np.mean(dy_list))
    rms = float(np.sqrt(np.mean(np.array(dx_list)**2 + np.array(dy_list)**2)))
    max_off = float(np.max(np.sqrt(np.array(dx_list)**2 + np.array(dy_list)**2)))
else:
    mean_dx, mean_dy, rms, max_off = 0.0, 0.0, 0.0, 0.0

ground_truth = {
    "stars_matched": len(dx_list),
    "mean_dx": mean_dx,
    "mean_dy": mean_dy,
    "rms_offset": rms,
    "max_offset": max_off,
    "aligned": bool(rms < 1.5)
}

with open("/tmp/alignment_ground_truth.json", "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground Truth Computed: {ground_truth}")
PYEOF

# Ensure ground truth is accessible but not immediately visible
chmod 644 /tmp/alignment_ground_truth.json

# ==============================================================================
# Launch Application
# ==============================================================================
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize Window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="