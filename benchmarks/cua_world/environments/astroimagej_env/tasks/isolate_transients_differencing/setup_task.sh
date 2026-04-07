#!/bin/bash
echo "=== Setting up Isolate Transients Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time

# Setup Directories
WORK_DIR="/home/ga/AstroImages/transient_search"
FRAMES_DIR="$WORK_DIR/frames"
OUTPUT_DIR="$WORK_DIR/output"

rm -rf "$WORK_DIR"
mkdir -p "$FRAMES_DIR" "$OUTPUT_DIR"

# Ensure we have the WASP-12b dataset available
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"
WASP12_URL="https://www.astro.louisville.edu/software/astroimagej/examples/WASP-12b_example_calibrated_images.tar.gz"

if [ -f "$WASP12_CACHE" ]; then
    echo "Extracting frames from cached WASP-12b data..."
    mkdir -p /tmp/wasp_extract
    tar -xzf "$WASP12_CACHE" -C /tmp/wasp_extract
else
    echo "Downloading WASP-12b data (not found in cache)..."
    mkdir -p /tmp/wasp_extract
    wget -q "$WASP12_URL" -O /tmp/wasp12b.tar.gz
    tar -xzf /tmp/wasp12b.tar.gz -C /tmp/wasp_extract
    rm -f /tmp/wasp12b.tar.gz
fi

# Move exactly 20 FITS files for the stack processing
echo "Preparing image sequence..."
find /tmp/wasp_extract -name "*.fits" -o -name "*.fit" | sort | head -n 20 | xargs -I {} mv {} "$FRAMES_DIR"/
rm -rf /tmp/wasp_extract

FITS_COUNT=$(ls -1 "$FRAMES_DIR"/*.fits 2>/dev/null | wc -l || echo "0")
echo "Loaded $FITS_COUNT FITS files in frames directory."

# Compute ground truth mathematically (Hidden from agent)
echo "Computing ground truth arrays..."
python3 << 'PYEOF'
import os, glob, json
import numpy as np
from astropy.io import fits

frames_dir = "/home/ga/AstroImages/transient_search/frames"
files = sorted(glob.glob(os.path.join(frames_dir, "*.fits")))

if not files:
    print("Error: No FITS files found for GT computation!")
    exit(1)

# Read all data
data = []
for f in files:
    data.append(fits.getdata(f).astype(np.float32))
data = np.array(data)

# Compute true mathematical projections
gt_median = np.median(data, axis=0)
gt_max = np.max(data, axis=0)
gt_diff = gt_max - gt_median
max_transient = float(np.max(gt_diff))

# Save GT out to /tmp for verification
fits.writeto('/tmp/gt_median.fits', gt_median, overwrite=True)
fits.writeto('/tmp/gt_max.fits', gt_max, overwrite=True)
fits.writeto('/tmp/gt_diff.fits', gt_diff, overwrite=True)

with open('/tmp/transient_ground_truth.json', 'w') as f:
    json.dump({"max_transient_value": max_transient}, f)
print(f"Ground truth mathematical max transient isolated: {max_transient}")
PYEOF

chown -R ga:ga "$WORK_DIR"

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize AIJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot showing clean starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="