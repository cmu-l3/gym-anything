#!/bin/bash
echo "=== Setting up CV Variability Mapping Task ==="

source /workspace/scripts/task_utils.sh

STACK_DIR="/home/ga/AstroImages/time_series_stack"
OUTPUT_DIR="/home/ga/AstroImages/cv_output"

rm -rf "$STACK_DIR" "$OUTPUT_DIR"
mkdir -p "$STACK_DIR" "$OUTPUT_DIR"

# Extract and prepare the real WASP-12b images
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ ! -f "$WASP12_CACHE" ]; then
    echo "ERROR: WASP-12b data not found at $WASP12_CACHE"
    exit 1
fi

echo "Extracting and processing WASP-12b images..."
python3 << 'PYEOF'
import os, glob, subprocess
from astropy.io import fits
import numpy as np

WASP12_CACHE = "/opt/fits_samples/WASP-12b_calibrated.tar.gz"
WORK_DIR = "/home/ga/AstroImages/time_series_stack"

# Extract to /tmp
subprocess.run(["tar", "-xzf", WASP12_CACHE, "-C", "/tmp"], check=True)

# Find FITS files
fits_files = sorted(glob.glob("/tmp/WASP-12b/*.fits"))[:40]
print(f"Processing {len(fits_files)} frames...")

for i, f in enumerate(fits_files):
    with fits.open(f) as hdul:
        data = hdul[0].data
        # Crop to central 1024x1024 for memory efficiency
        h, w = data.shape
        cy, cx = h//2, w//2
        cropped = data[cy-512:cy+512, cx-512:cx+512]
        
        out_f = os.path.join(WORK_DIR, f"frame_{i+1:03d}.fits")
        fits.writeto(out_f, cropped, hdul[0].header, overwrite=True)

subprocess.run(["rm", "-rf", "/tmp/WASP-12b"])
PYEOF

chown -R ga:ga "$STACK_DIR"
chown -R ga:ga "$OUTPUT_DIR"

# Record initial state
date +%s > /tmp/task_start_timestamp

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="