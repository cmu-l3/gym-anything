#!/bin/bash
echo "=== Setting up CCD Gain Measurement Task ==="

source /workspace/scripts/task_utils.sh

WORK_DIR="/home/ga/AstroImages/gain_measurement"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# 1. Use Python to prepare real Palomar LFC data and compute Ground Truth
echo "Preparing data and computing ground truth..."
python3 << 'PYEOF'
import os
import glob
import json
import shutil
import numpy as np
from astropy.io import fits

LFC_DIR = "/opt/fits_samples/palomar_lfc"
WORK_DIR = "/home/ga/AstroImages/gain_measurement"

# Find FITS files
all_fits = glob.glob(os.path.join(LFC_DIR, "**/*.fits"), recursive=True) + \
           glob.glob(os.path.join(LFC_DIR, "**/*.fit"), recursive=True)

bias_files = []
flat_files = []

for f in all_fits:
    try:
        hdr = fits.getheader(f)
        itype = hdr.get('IMAGETYP', '').upper()
        if 'BIAS' in itype:
            bias_files.append(f)
        elif 'FLAT' in itype:
            flat_files.append(f)
    except Exception:
        pass

# Fallback if IMAGETYP is missing but filenames are descriptive
if not bias_files:
    bias_files = [f for f in all_fits if 'bias' in os.path.basename(f).lower()]
if not flat_files:
    flat_files = [f for f in all_fits if 'flat' in os.path.basename(f).lower()]

if len(bias_files) < 1 or len(flat_files) < 2:
    print(f"ERROR: Insufficient data. Found {len(bias_files)} biases, {len(flat_files)} flats.")
    # In a true failure, we'd exit, but we assume environment prep worked.
    exit(1)

# Sort and select frames
bias_files = sorted(bias_files)[:10]  # Use up to 10 for master bias
flat_files = sorted(flat_files)[:2]   # Pick 2 flats

print(f"Using {len(bias_files)} bias frames and 2 flat frames.")

# Create Master Bias
bias_data = [fits.getdata(f).astype(float) for f in bias_files]
master_bias = np.median(bias_data, axis=0)

# Write Master Bias
mb_path = os.path.join(WORK_DIR, "master_bias.fits")
fits.writeto(mb_path, master_bias.astype(np.float32), overwrite=True)

# Copy the two flats
f1_path = os.path.join(WORK_DIR, "flat_1.fits")
f2_path = os.path.join(WORK_DIR, "flat_2.fits")
shutil.copy2(flat_files[0], f1_path)
shutil.copy2(flat_files[1], f2_path)

# ---------------------------------------------------------
# Compute Ground Truth (in central 500x500 ROI)
# ---------------------------------------------------------
flat1 = fits.getdata(f1_path).astype(float)
flat2 = fits.getdata(f2_path).astype(float)

h, w = flat1.shape
cy, cx = h // 2, w // 2
half_roi = 250

# Ensure ROI fits in image
cy = max(half_roi, min(h - half_roi, cy))
cx = max(half_roi, min(w - half_roi, cx))

# Bias subtract
f1_sub = flat1 - master_bias
f2_sub = flat2 - master_bias

# Extract ROI
roi_f1 = f1_sub[cy-half_roi:cy+half_roi, cx-half_roi:cx+half_roi]
roi_f2 = f2_sub[cy-half_roi:cy+half_roi, cx-half_roi:cx+half_roi]

# Calculate stats
mean1 = np.mean(roi_f1)
mean2 = np.mean(roi_f2)
mean_signal = float((mean1 + mean2) / 2.0)

diff = roi_f1 - roi_f2
diff_std = float(np.std(diff))
diff_var = diff_std ** 2

gain = float(2.0 * mean_signal / diff_var)

gt = {
    "roi_center_y": cy,
    "roi_center_x": cx,
    "mean_signal_adu": mean_signal,
    "difference_stddev_adu": diff_std,
    "difference_variance_adu2": diff_var,
    "gain_e_per_adu": gain,
    "image_shape": [h, w]
}

with open('/tmp/ccd_gain_ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=4)

print(f"Ground truth calculated: Gain = {gain:.3f} e-/ADU")
PYEOF

chown -R ga:ga "$WORK_DIR"

# 2. Create instructions file
cat > "$WORK_DIR/README_instructions.txt" << 'EOF'
CCD Gain Measurement via Photon Transfer Method
===============================================

You have two flat-field frames (flat_1.fits, flat_2.fits) and a master_bias.fits.

Formula to compute gain (e-/ADU):
  1. Subtract master_bias from both flats (F1 = flat_1 - bias, F2 = flat_2 - bias)
  2. Measure mean of F1 and mean of F2 in a central 500x500 pixel region.
  3. Average these to get the overall mean signal (S).
  4. Create difference image: Diff = F1 - F2
  5. Measure standard deviation of Diff in the EXACT SAME 500x500 region.
  6. Calculate Variance = (Standard Deviation)^2
  7. Gain = 2 * S / Variance

Record your results in ccd_gain_results.txt using this exact format:
mean_signal_adu: <value>
difference_stddev_adu: <value>
difference_variance_adu2: <value>
gain_e_per_adu: <value>
EOF
chown ga:ga "$WORK_DIR/README_instructions.txt"

# 3. Setup anti-gaming records
date +%s > /tmp/task_start_time.txt
rm -f "$WORK_DIR/ccd_gain_results.txt" 2>/dev/null || true

# 4. Launch AstroImageJ (empty state)
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize and Focus
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="