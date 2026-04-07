#!/bin/bash
echo "=== Setting up simulate_ground_based_observation task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create directories
SIM_DIR="/home/ga/AstroImages/simulations"
OUT_DIR="$SIM_DIR/output"
rm -rf "$SIM_DIR"
mkdir -p "$OUT_DIR"

# Provide the real HST Eagle Nebula FITS file
# (This file is pre-cached during environment installation)
EAGLE_SRC="/opt/fits_samples/eagle_nebula/656nmos.fits"
TARGET_FILE="$SIM_DIR/hst_eagle_halpha.fits"

if [ -f "$EAGLE_SRC" ]; then
    cp "$EAGLE_SRC" "$TARGET_FILE"
else
    echo "WARNING: Pre-cached Eagle Nebula file not found. Falling back to generic WFPC2 sample."
    cp "/opt/fits_samples/hst_wfpc2_sample.fits" "$TARGET_FILE"
fi

chown -R ga:ga "$SIM_DIR"

# Pre-calculate Ground Truth using Python (Astropy + Scipy)
# This prevents hardcoding and adapts to whichever FITS file is loaded
python3 << 'PYEOF'
import json
import numpy as np
from astropy.io import fits
from scipy.ndimage import gaussian_filter, zoom

target_file = "/home/ga/AstroImages/simulations/hst_eagle_halpha.fits"

try:
    with fits.open(target_file) as hdul:
        data = hdul[0].data.astype(float)
        
    orig_max = float(np.nanmax(data))
    orig_h, orig_w = data.shape

    # Simulate AstroImageJ's Gaussian Blur (sigma=12.0)
    blurred = gaussian_filter(data, sigma=12.0)
    
    # Simulate AstroImageJ's Scale to 20% (0.2)
    scaled = zoom(blurred, 0.2, order=1)
    
    expected_max = float(np.nanmax(scaled))
    expected_h, expected_w = scaled.shape
    
    gt = {
        "orig_w": orig_w,
        "orig_h": orig_h,
        "orig_max": orig_max,
        "expected_w": expected_w,
        "expected_h": expected_h,
        "expected_max": expected_max,
        "status": "success"
    }
except Exception as e:
    gt = {"status": "error", "message": str(e)}

with open("/tmp/sim_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)
PYEOF

# Launch AstroImageJ
launch_astroimagej 60

# Maximize the window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="