#!/bin/bash
echo "=== Setting up Eagle Nebula Line Profile Task ==="

source /workspace/scripts/task_utils.sh

# Setup directories
TASK_DIR="/home/ga/AstroImages/line_profile_task"
MEASURE_DIR="/home/ga/AstroImages/measurements"
rm -rf "$TASK_DIR" "$MEASURE_DIR"
mkdir -p "$TASK_DIR" "$MEASURE_DIR"

# FITS source
EAGLE_SRC="/opt/fits_samples/eagle_nebula/656nmos.fits"
EAGLE_ZIP="/opt/fits_samples/eagle_nebula/656nmos.zip"

if [ ! -f "$EAGLE_SRC" ]; then
    if [ -f "$EAGLE_ZIP" ]; then
        unzip -o "$EAGLE_ZIP" -d "/opt/fits_samples/eagle_nebula/"
    else
        echo "ERROR: FITS file not found and no zip available."
        exit 1
    fi
fi

# Copy FITS to working directory
cp "$EAGLE_SRC" "$TASK_DIR/656nmos.fits"

# Calculate ground truth and generate instructions
python3 << 'PYEOF'
import json
import os
import numpy as np
from astropy.io import fits

fits_path = "/home/ga/AstroImages/line_profile_task/656nmos.fits"
with fits.open(fits_path) as hdul:
    data = hdul[0].data.astype(float)

h, w = data.shape

# Pick a row in the middle third with high variation (crosses a pillar)
mid_start, mid_end = h // 3, 2 * h // 3
row_stds = [np.nanstd(data[r, :]) for r in range(mid_start, mid_end)]
best_row = mid_start + int(np.argmax(row_stds))

# Extract the profile
profile = data[best_row, :]
valid_profile = profile[~np.isnan(profile)]

peak_val = float(np.nanmax(profile))
peak_x = int(np.nanargmax(profile))

# Background: mean of the lowest 25% of pixels
sorted_vals = np.sort(valid_profile)
bg_mean = float(np.mean(sorted_vals[:len(sorted_vals)//4]))

# Simple FWHM calculation around the peak feature
half_max = (peak_val + bg_mean) / 2.0
# Find left bound
left_idx = peak_x
while left_idx > 0 and profile[left_idx] > half_max:
    left_idx -= 1
# Find right bound
right_idx = peak_x
while right_idx < w - 1 and profile[right_idx] > half_max:
    right_idx += 1

fwhm = float(right_idx - left_idx)

gt = {
    "target_row": int(best_row),
    "image_width": int(w),
    "peak_intensity": peak_val,
    "peak_position_x": peak_x,
    "mean_background": bg_mean,
    "fwhm_pixels": fwhm
}

# Save ground truth (hidden from agent)
with open("/tmp/line_profile_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)

# Save instructions for agent
instructions = f"""Eagle Nebula H-alpha Line Profile Extraction

Target Row (Y-coordinate): {best_row}

Please draw a horizontal line across the entire image at exactly Y={best_row}.
Extract the profile and save the data and summary as requested.
"""
with open("/home/ga/AstroImages/line_profile_task/profile_instructions.txt", "w") as f:
    f.write(instructions)

PYEOF

chown -R ga:ga "$TASK_DIR" "$MEASURE_DIR"

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time

# Close any existing AstroImageJ
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

# Launch AstroImageJ directly opening the FITS file
AIJ_PATH=$(find /opt/astroimagej -name "AstroImageJ" -type f -executable | head -1)
if [ -z "$AIJ_PATH" ]; then
    AIJ_PATH="/usr/local/bin/aij"
fi

su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx2g' '$AIJ_PATH' '$TASK_DIR/656nmos.fits' > /tmp/astroimagej_ga.log 2>&1" &

# Wait for AIJ to load the image
sleep 8
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "656nmos"; then
        break
    fi
    sleep 1
done

# Maximize the window for the agent
WID=$(DISPLAY=:1 wmctrl -l | grep -i "656nmos" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Final screenshot of initial state
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="