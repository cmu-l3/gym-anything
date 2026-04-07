#!/bin/bash
echo "=== Setting up Rolling Ball Background Subtraction task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/AstroImages/gradient_removal"
OUTPUT_DIR="$PROJECT_DIR/output"

# Clean up and recreate directories
rm -rf "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Anti-gaming timestamp
date +%s > /tmp/task_start_time

echo "Fetching FITS file..."
# Fetch the M12 Vcomb.fits
if [ -f "/opt/fits_samples/m12/Vcomb.fits" ]; then
    cp "/opt/fits_samples/m12/Vcomb.fits" "$PROJECT_DIR/Vcomb.fits"
else
    # Fallback to synthesizing a gradient image if the dataset is missing
    echo "WARNING: Vcomb.fits not found. Synthesizing test gradient image..."
    python3 -c "
import numpy as np
from astropy.io import fits
import os

y, x = np.mgrid[0:1000, 0:1000]
r = np.sqrt((x-500)**2 + (y-500)**2)
bg = 2000 * np.exp(-r/300)
noise = np.random.normal(0, 5, (1000, 1000))
stars = np.zeros((1000, 1000))
for _ in range(300):
    sx, sy = np.random.randint(0, 1000, 2)
    stars[sy, sx] = np.random.uniform(500, 5000)
data = bg + noise + stars
fits.writeto('$PROJECT_DIR/Vcomb.fits', data.astype(np.float32), overwrite=True)
"
fi
chown ga:ga "$PROJECT_DIR/Vcomb.fits"

echo "Calculating initial statistics..."
# Calculate initial statistics using Python to establish ground truth baseline
python3 << 'PYEOF'
import json, os
import numpy as np
from astropy.io import fits

filepath = "/home/ga/AstroImages/gradient_removal/Vcomb.fits"
if os.path.exists(filepath):
    data = fits.getdata(filepath).astype(float)
    if data.ndim == 3:
        data = data[0]
    
    h, w = data.shape
    cy, cx = h//2, w//2
    
    # Measure a 200x200 center region and a corner region
    center_region = data[max(0, cy-100):min(h, cy+100), max(0, cx-100):min(w, cx+100)]
    corner_region = data[max(0, 50):min(h, 250), max(0, 50):min(w, 250)]
    
    initial_center_median = float(np.nanmedian(center_region))
    initial_corner_median = float(np.nanmedian(corner_region))
    initial_gradient = abs(initial_center_median - initial_corner_median)
    
    stats = {
        "initial_center_median": initial_center_median,
        "initial_corner_median": initial_corner_median,
        "initial_gradient": initial_gradient
    }
    with open("/tmp/initial_stats.json", "w") as f:
        json.dump(stats, f)
PYEOF

echo "Starting AstroImageJ..."
# Launch AstroImageJ
launch_astroimagej 60

# Maximize Window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="