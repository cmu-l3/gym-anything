#!/bin/bash
echo "=== Setting up Galaxy Half-Light Radius Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
RAW_DIR="/home/ga/AstroImages/raw"
MEASURE_DIR="/home/ga/AstroImages/measurements"
mkdir -p "$RAW_DIR" "$MEASURE_DIR"
rm -f "$MEASURE_DIR/half_light_radius.txt"

# Ensure FITS file is available
FITS_SRC="/opt/fits_samples/uit_galaxy_sample.fits"
FITS_DEST="$RAW_DIR/uit_galaxy_sample.fits"

if [ -f "$FITS_SRC" ]; then
    cp "$FITS_SRC" "$FITS_DEST"
else
    echo "ERROR: uit_galaxy_sample.fits not found in /opt/fits_samples/"
    exit 1
fi

chown -R ga:ga /home/ga/AstroImages

# Compute Ground Truth dynamically from the real FITS file
echo "Computing ground truth..."
python3 << 'PYEOF'
import json
import numpy as np
from astropy.io import fits

fits_file = "/home/ga/AstroImages/raw/uit_galaxy_sample.fits"

try:
    data = fits.getdata(fits_file).astype(float)
    if data.ndim > 2:
        data = data[0]

    h, w = data.shape

    # Sky background mean (Top left 50x50)
    bg_data = data[0:50, 0:50]
    bg_mean = float(np.mean(bg_data))

    # Center finding
    cy_est, cx_est = h // 2, w // 2
    # Search within center 200x200
    search_box = data[cy_est-100:cy_est+100, cx_est-100:cx_est+100]
    py, px = np.unravel_index(np.argmax(search_box), search_box.shape)
    
    # AstroImageJ (ImageJ) uses 0-based coordinates, X is column, Y is row
    center_y = int(cy_est - 100 + py)
    center_x = int(cx_est - 100 + px)

    # Calculate exact flux within radius R
    def get_flux(r):
        y, x = np.ogrid[0:h, 0:w]
        mask = (x - center_x)**2 + (y - center_y)**2 <= r**2
        raw_int_den = np.sum(data[mask])
        area = np.sum(mask)
        return float(raw_int_den - (bg_mean * area))

    total_flux_120 = get_flux(120)
    target_flux = total_flux_120 / 2.0

    # Iterative search for half-light radius
    best_r = 1
    min_diff = float('inf')
    for r in range(1, 121):
        flux_r = get_flux(r)
        diff = abs(flux_r - target_flux)
        if diff < min_diff:
            min_diff = diff
            best_r = r

    gt = {
        "sky_background_mean": bg_mean,
        "center_x": center_x,
        "center_y": center_y,
        "total_flux_r120": total_flux_120,
        "half_light_radius": best_r
    }

    with open("/tmp/ground_truth.json", "w") as f:
        json.dump(gt, f, indent=2)

    print(f"Ground truth calculated: Center ({center_x}, {center_y}), R_e={best_r}")
except Exception as e:
    print(f"Failed to calculate ground truth: {e}")
PYEOF

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize AstroImageJ
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="