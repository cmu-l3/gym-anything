#!/bin/bash
echo "=== Setting up Emission Line Subtraction Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Setup directories
WORK_DIR="/home/ga/AstroImages/eagle_subtraction"
OUTPUT_DIR="$WORK_DIR/output"
rm -rf "$WORK_DIR"
mkdir -p "$OUTPUT_DIR"

# Copy data from environment cache
EAGLE_SRC="/opt/fits_samples/eagle_nebula"

# Ensure data is available (download if missing from cache)
if [ ! -f "$EAGLE_SRC/656nmos.fits" ] || [ ! -f "$EAGLE_SRC/502nmos.fits" ]; then
    echo "Eagle nebula FITS not found at $EAGLE_SRC. Downloading..."
    mkdir -p "$EAGLE_SRC"
    for filter in 502nmos 656nmos; do
        if [ ! -f "$EAGLE_SRC/${filter}.fits" ]; then
            wget -q --timeout=60 "https://esahubble.org/static/projects/fits_liberator/datasets/eagle/${filter}.zip" -O "/tmp/${filter}.zip" || true
            if [ -f "/tmp/${filter}.zip" ]; then
                unzip -q -o "/tmp/${filter}.zip" -d "$EAGLE_SRC"
                rm "/tmp/${filter}.zip"
            fi
        fi
    done
fi

cp "$EAGLE_SRC/656nmos.fits" "$WORK_DIR/"
cp "$EAGLE_SRC/502nmos.fits" "$WORK_DIR/"

# Create instructions hint file for the agent
cat > "$WORK_DIR/instructions.txt" << 'EOF'
Task: Emission-Line Difference Image
1. Open 656nmos.fits (H-alpha) and 502nmos.fits ([OIII]).
2. Find the median pixel value of each.
3. Calculate scale factor = median(H-alpha) / median([OIII]).
4. Multiply [OIII] by the scale factor.
5. Subtract scaled [OIII] from H-alpha using Process > Image Calculator.
6. Save the difference image to output/halpha_minus_oiii.fits
7. Write output/difference_report.txt with medians, scale factor, and difference stats.
EOF

# Calculate ground truth natively (hidden from agent)
python3 << 'PYEOF'
import os
import json
import numpy as np
try:
    from astropy.io import fits
    
    WORK_DIR = "/home/ga/AstroImages/eagle_subtraction"
    ha_file = os.path.join(WORK_DIR, "656nmos.fits")
    oiii_file = os.path.join(WORK_DIR, "502nmos.fits")
    
    ha_data = fits.getdata(ha_file).astype(float)
    oiii_data = fits.getdata(oiii_file).astype(float)
    
    ha_median = float(np.nanmedian(ha_data))
    oiii_median = float(np.nanmedian(oiii_data))
    
    scale_factor = ha_median / oiii_median if oiii_median != 0 else 1.0
    
    diff_data = ha_data - (scale_factor * oiii_data)
    
    diff_mean = float(np.nanmean(diff_data))
    diff_std = float(np.nanstd(diff_data))
    diff_min = float(np.nanmin(diff_data))
    diff_max = float(np.nanmax(diff_data))
    diff_median = float(np.nanmedian(diff_data))
    
    gt = {
        "ha_median": ha_median,
        "oiii_median": oiii_median,
        "scale_factor": scale_factor,
        "diff_mean": diff_mean,
        "diff_std": diff_std,
        "diff_min": diff_min,
        "diff_max": diff_max,
        "diff_median": diff_median,
        "image_shape": list(ha_data.shape)
    }
    
    with open('/tmp/emission_diff_ground_truth.json', 'w') as f:
        json.dump(gt, f, indent=2)
except Exception as e:
    print(f"Error computing ground truth: {e}")
PYEOF

chown -R ga:ga "$WORK_DIR"

# Launch AstroImageJ
echo "Launching AstroImageJ..."
if type launch_astroimagej &>/dev/null; then
    launch_astroimagej 120
else
    # Fallback if utils missing
    su - ga -c "DISPLAY=:1 /usr/local/bin/aij &"
    sleep 10
fi

sleep 2
if type get_aij_window_id &>/dev/null; then
    WID=$(get_aij_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        focus_window "$WID"
    fi
else
    DISPLAY=:1 wmctrl -r "AstroImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Capture initial state for evidence
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="