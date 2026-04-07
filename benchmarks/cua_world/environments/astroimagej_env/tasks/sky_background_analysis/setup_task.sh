#!/bin/bash
echo "=== Setting up Sky Background Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/AstroImages/raw
mkdir -p /home/ga/AstroImages/measurements
chown -R ga:ga /home/ga/AstroImages

# Clean up any previous runs
rm -f /home/ga/AstroImages/measurements/sky_background_report.txt
rm -f /tmp/sky_bg_ground_truth.json
rm -f /tmp/task_result.json

# Ensure FITS file exists
FITS_FILE="/home/ga/AstroImages/raw/hst_wfpc2_sample.fits"
if [ ! -f "$FITS_FILE" ]; then
    if [ -f "/opt/fits_samples/hst_wfpc2_sample.fits" ]; then
        cp /opt/fits_samples/hst_wfpc2_sample.fits "$FITS_FILE"
        chown ga:ga "$FITS_FILE"
    else
        echo "ERROR: Could not find HST WFPC2 sample file!"
        exit 1
    fi
fi

# Calculate Ground Truth from the actual FITS data
echo "Calculating ground truth from FITS data..."
python3 << 'PYEOF'
import json
import os
import numpy as np

try:
    from astropy.io import fits
    from astropy.stats import sigma_clipped_stats
    
    fits_path = "/home/ga/AstroImages/raw/hst_wfpc2_sample.fits"
    with fits.open(fits_path) as hdul:
        # Usually science data is in the primary or first extension
        data = hdul[0].data if hdul[0].data is not None else hdul[1].data
        
        # Calculate sigma clipped statistics (robust against stars/cosmic rays)
        mean, median, std = sigma_clipped_stats(data, sigma=3.0, maxiters=5)
        
        # Get peak value (brightest star/pixel)
        peak = np.nanmax(data)
        
        gt = {
            "background_median": float(median),
            "rms_stddev": float(std),
            "peak_value": float(peak),
            "expected_snr": float((peak - median) / std) if std > 0 else 0.0
        }
        
        with open("/tmp/sky_bg_ground_truth.json", "w") as f:
            json.dump(gt, f, indent=2)
            
        print(f"Ground truth calculated: Bg={median:.2f}, RMS={std:.2f}, Peak={peak:.2f}")
        
except Exception as e:
    print(f"Error calculating ground truth: {e}")
    # Fallback values if astropy fails
    fallback_gt = {
        "background_median": 45.0,
        "rms_stddev": 5.0,
        "peak_value": 4000.0,
        "expected_snr": 791.0
    }
    with open("/tmp/sky_bg_ground_truth.json", "w") as f:
        json.dump(fallback_gt, f, indent=2)
PYEOF

# Create AstroImageJ macro to open the FITS file
MACRO_FILE="/tmp/open_fits.ijm"
cat > "$MACRO_FILE" << EOF
open("$FITS_FILE");
run("Enhance Contrast", "saturated=0.35");
EOF
chown ga:ga "$MACRO_FILE"

# Launch AstroImageJ with the macro
echo "Launching AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 1

# Find executable
AIJ_PATH=$(find /opt/astroimagej /usr/local/bin -name "AstroImageJ" -o -name "aij" -type f -executable 2>/dev/null | head -1)

if [ -n "$AIJ_PATH" ]; then
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx2g' '$AIJ_PATH' -macro '$MACRO_FILE' > /tmp/astroimagej_ga.log 2>&1" &
    
    # Wait for AstroImageJ to start
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "hst_wfpc2\|ImageJ\|AstroImageJ"; then
            break
        fi
        sleep 1
    done
    
    sleep 3
    
    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "hst_wfpc2\|AstroImageJ" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    fi
else
    echo "ERROR: AstroImageJ executable not found"
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="