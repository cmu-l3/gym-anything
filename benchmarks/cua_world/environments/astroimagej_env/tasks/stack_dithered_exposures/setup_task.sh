#!/bin/bash
echo "=== Setting up Stack Dithered Exposures Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Setup directories
DITHER_DIR="/home/ga/AstroImages/dithered_sequence"
PROCESSED_DIR="/home/ga/AstroImages/processed"
rm -rf "$DITHER_DIR" "$PROCESSED_DIR"
mkdir -p "$DITHER_DIR" "$PROCESSED_DIR"
chown ga:ga /home/ga/AstroImages

echo "Generating dithered sequence from real WASP-12b data..."

# Use python to extract a real FITS frame and generate dithered copies
python3 << 'PYEOF'
import os
import json
import subprocess
from astropy.io import fits
import numpy as np
from scipy.ndimage import shift

WASP12_CACHE = "/opt/fits_samples/WASP-12b_calibrated.tar.gz"
DITHER_DIR = "/home/ga/AstroImages/dithered_sequence"

# Extract one file from the cached WASP-12b tarball
if os.path.exists(WASP12_CACHE):
    subprocess.run(["tar", "-xzf", WASP12_CACHE, "-C", "/tmp", "WASP-12b/WASP-12b-0001.fits"], check=False)
    base_file = "/tmp/WASP-12b/WASP-12b-0001.fits"
else:
    print("WARNING: WASP-12b cache not found, looking for alternative FITS")
    # Fallback if cache is missing
    base_file = "/opt/fits_samples/hst_wfpc2_sample.fits"

if not os.path.exists(base_file):
    print("ERROR: No base FITS file found to generate task data.")
    sys.exit(1)

# Read image
data = fits.getdata(base_file).astype(np.float32)
hdr = fits.getheader(base_file)

# Crop to a 1000x1000 region for faster processing and clean edges during shifts
cy, cx = data.shape[0]//2, data.shape[1]//2
data_crop = data[cy-500:cy+500, cx-500:cx+500]

# Define significant integer pixel shifts (simulate poor telescope tracking/dithering)
shifts = [(0, 0), (12, -15), (-20, 8), (5, 25), (-18, -12)]

for i, (dy, dx) in enumerate(shifts):
    # Shift image
    shifted = shift(data_crop, (dy, dx), order=1, mode='reflect')
    
    # Add slight independent noise so frames aren't mathematically identical
    # This prevents the agent from simply copying one frame and passing noise checks
    noise = np.random.normal(0, max(np.std(data_crop)*0.05, 1.0), shifted.shape)
    shifted += noise
    
    out_path = os.path.join(DITHER_DIR, f"frame_{i+1:03d}.fits")
    fits.writeto(out_path, shifted.astype(np.float32), hdr, overwrite=True)
    os.chmod(out_path, 0o644)
    shutil.chown(out_path, "ga", "ga")

print(f"Generated {len(shifts)} dithered frames in {DITHER_DIR}")

# Save ground truth details
with open('/tmp/ground_truth.json', 'w') as f:
    json.dump({"num_frames": len(shifts), "shifts": shifts}, f)

PYEOF

chown -R ga:ga "$DITHER_DIR"
chown -R ga:ga "$PROCESSED_DIR"

echo "Launching AstroImageJ..."
launch_astroimagej 120

sleep 3
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="