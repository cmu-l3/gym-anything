#!/bin/bash
echo "=== Setting up Logarithmic Intensity Rescaling Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# Create working directories
WORK_DIR="/home/ga/AstroImages/eagle_log"
OUT_DIR="$WORK_DIR/output"
rm -rf "$WORK_DIR"
mkdir -p "$OUT_DIR"

# Copy source FITS file
SRC_FITS="/opt/fits_samples/eagle_nebula/656nmos.fits"
DEST_FITS="$WORK_DIR/eagle_halpha.fits"

if [ -f "$SRC_FITS" ]; then
    cp "$SRC_FITS" "$DEST_FITS"
else
    echo "WARNING: Pre-installed 656nmos.fits not found, downloading directly..."
    wget -q --timeout=60 "https://esahubble.org/static/projects/fits_liberator/datasets/eagle/656nmos.zip" -O /tmp/656nmos.zip
    if [ -f "/tmp/656nmos.zip" ]; then
        unzip -q -j /tmp/656nmos.zip -d "$WORK_DIR"
        mv "$WORK_DIR/656nmos.fits" "$DEST_FITS" 2>/dev/null || true
    else
        echo "CRITICAL: Could not download data file. Task cannot proceed correctly."
        # Create dummy FITS just so AIJ doesn't crash completely, though the task will be impossible
        python3 -c "import numpy as np; from astropy.io import fits; fits.writeto('$DEST_FITS', np.random.rand(800, 800)*1000)"
    fi
fi

# Set permissions
chown -R ga:ga "$WORK_DIR"

# Compute ground truth from the real FITS file
echo "Computing ground truth statistics..."
python3 << 'PYEOF'
import json
import os
import numpy as np
from astropy.io import fits

filepath = "/home/ga/AstroImages/eagle_log/eagle_halpha.fits"
gt = {}

try:
    with fits.open(filepath) as hdul:
        # Use first HDU with data
        for hdu in hdul:
            if hdu.data is not None:
                data = hdu.data.astype(np.float64)
                # Filter out NaNs if any exist
                valid_data = data[~np.isnan(data)]
                
                gt['orig_min'] = float(np.min(valid_data))
                gt['orig_max'] = float(np.max(valid_data))
                gt['orig_mean'] = float(np.mean(valid_data))
                gt['orig_std'] = float(np.std(valid_data))
                
                # Apply log1p transform exactly as instructed: log(1+x) * 10000
                # Using np.clip to prevent log(<0) issues if negative pixels exist
                safe_data = np.clip(valid_data, 0, None)
                trans_data = np.log(1 + safe_data) * 10000.0
                
                gt['trans_min'] = float(np.min(trans_data))
                gt['trans_max'] = float(np.max(trans_data))
                gt['trans_mean'] = float(np.mean(trans_data))
                gt['trans_std'] = float(np.std(trans_data))
                
                gt['dr_orig'] = gt['orig_max'] / gt['orig_mean'] if gt['orig_mean'] != 0 else 0
                gt['dr_trans'] = gt['trans_max'] / gt['trans_mean'] if gt['trans_mean'] != 0 else 0
                break
                
    with open('/tmp/log_scale_ground_truth.json', 'w') as f:
        json.dump(gt, f, indent=2)
    print("Ground truth computed successfully")
except Exception as e:
    print(f"Error computing ground truth: {e}")
PYEOF

chmod 644 /tmp/log_scale_ground_truth.json 2>/dev/null || true

# Start AstroImageJ and maximize it
echo "Launching AstroImageJ..."
launch_astroimagej 120

sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="