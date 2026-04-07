#!/bin/bash
echo "=== Setting up Time-Series Stacking Diagnostics Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AstroImages/stack_diagnostics"
FRAMES_DIR="$PROJECT_DIR/frames"
RESULTS_DIR="$PROJECT_DIR/results"

rm -rf "$PROJECT_DIR"
mkdir -p "$FRAMES_DIR" "$RESULTS_DIR"

# Extract exactly 10 FITS frames from the cached dataset
TARBALL="/opt/fits_samples/WASP-12b_calibrated.tar.gz"
if [ -f "$TARBALL" ]; then
    echo "Extracting 10 frames from WASP-12b data..."
    tar -tzf "$TARBALL" | grep -i "\.fits$" | sort | head -n 10 > /tmp/wasp_10_files.txt
    tar -xzf "$TARBALL" -T /tmp/wasp_10_files.txt -C /tmp/
    find /tmp/WASP-12b -name "*.fits" -exec mv {} "$FRAMES_DIR/" \;
    rm -rf /tmp/WASP-12b /tmp/wasp_10_files.txt
else
    echo "WARNING: WASP-12b tarball not found. Trying hst sample..."
    HST="/opt/fits_samples/hst_wfpc2_sample.fits"
    if [ -f "$HST" ]; then
        for i in {1..10}; do
            cp "$HST" "$FRAMES_DIR/frame_$(printf "%02d" $i).fits"
        done
    else
        echo "ERROR: No FITS files available."
        exit 1
    fi
fi

chown -R ga:ga "$PROJECT_DIR"

# Compute ground truth
python3 << 'PYEOF'
import os, glob, json
import numpy as np
try:
    from astropy.io import fits
    
    frames_dir = "/home/ga/AstroImages/stack_diagnostics/frames"
    fits_files = sorted(glob.glob(os.path.join(frames_dir, "*.fits")))
    
    if len(fits_files) > 0:
        data = np.array([fits.getdata(f).astype(np.float32) for f in fits_files])
        # Calculate Average and Median stacks
        avg_stack = np.mean(data, axis=0)
        med_stack = np.median(data, axis=0)
        residual = avg_stack - med_stack
        
        gt = {
            "max_residual": float(np.max(residual)),
            "min_residual": float(np.min(residual)),
            "num_frames": len(fits_files)
        }
    else:
        gt = {"error": "No fits files found"}
        
    with open("/tmp/stack_diagnostics_truth.json", "w") as f:
        json.dump(gt, f, indent=2)
except Exception as e:
    with open("/tmp/stack_diagnostics_truth.json", "w") as f:
        json.dump({"error": str(e)}, f, indent=2)
PYEOF

chmod 644 /tmp/stack_diagnostics_truth.json

# Launch AstroImageJ
launch_astroimagej 120

# Maximize the AstroImageJ window for better agent interaction
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="