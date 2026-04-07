#!/bin/bash
# Setup script for Point Source Suppression task
set -euo pipefail

echo "=== Setting up Point Source Suppression Task ==="

source /workspace/scripts/task_utils.sh

WORK_DIR="/home/ga/AstroImages/nebula_analysis"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# 1. Prepare Data
# The image should be in the cache from install_astroimagej.sh
EAGLE_SRC="/opt/fits_samples/eagle_nebula/656nmos.fits"
EAGLE_DEST="$WORK_DIR/eagle_ha_656nmos.fits"

if [ -f "$EAGLE_SRC" ]; then
    cp "$EAGLE_SRC" "$EAGLE_DEST"
else
    echo "Warning: Cached Eagle Nebula file not found. Downloading..."
    wget -q --timeout=60 "https://esahubble.org/static/projects/fits_liberator/datasets/eagle/656nmos.zip" -O /tmp/656nmos.zip
    unzip -p /tmp/656nmos.zip 656nmos.fits > "$EAGLE_DEST"
fi

chown -R ga:ga "$WORK_DIR"

# 2. Compute Ground Truth (Hidden from Agent)
# Calculate original image stats to use for later comparison
python3 << 'PYEOF'
import json
import os
import numpy as np
from scipy import ndimage
try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

fpath = "/home/ga/AstroImages/nebula_analysis/eagle_ha_656nmos.fits"
gt = {"error": "astropy not available"}

if HAS_ASTROPY and os.path.exists(fpath):
    try:
        data = fits.getdata(fpath).astype(float)
        # Handle 3D data if any
        if data.ndim > 2:
            data = data[0]
            
        data = np.nan_to_num(data, nan=np.nanmedian(data))
        
        med_val = float(np.median(data))
        std_val = float(np.std(data))
        max_val = float(np.max(data))
        
        # Count bright point sources (stars)
        threshold = med_val + 5 * std_val
        labeled, num_features = ndimage.label(data > threshold)
        
        gt = {
            "original_median": med_val,
            "original_max": max_val,
            "original_std": std_val,
            "original_sources": int(num_features)
        }
    except Exception as e:
        gt = {"error": str(e)}

with open("/tmp/ground_truth.json", "w") as f:
    json.dump(gt, f)
PYEOF

chmod 644 /tmp/ground_truth.json

# 3. Record Initial State and Timestamp
date +%s > /tmp/task_start_timestamp

# 4. Launch AstroImageJ
# We launch AIJ but do NOT open the FITS file, the agent must do it.
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize Window
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png ga

echo "=== Task Setup Complete ==="