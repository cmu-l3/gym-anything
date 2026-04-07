#!/bin/bash
echo "=== Setting up Isolate Cluster Core Stars Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Create directories
PROJECT_DIR="/home/ga/AstroImages/core_isolation"
OUTPUT_DIR="$PROJECT_DIR/output"
rm -rf "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"

# Ensure input data exists (fallback just in case)
if [ ! -f /opt/fits_samples/m12/Vcomb.fits ]; then
    echo "Warning: /opt/fits_samples/m12/Vcomb.fits not found! Generating fallback data."
    mkdir -p /opt/fits_samples/m12
    python3 -c "import numpy as np; from astropy.io import fits; x, y = np.mgrid[0:500, 0:500]; data = np.exp(-((x-250)**2 + (y-250)**2)/10000.0)*1000 + np.random.normal(0, 10, (500,500)); fits.writeto('/opt/fits_samples/m12/Vcomb.fits', data.astype(np.float32), overwrite=True)"
fi

# Copy M12 Vcomb.fits
cp /opt/fits_samples/m12/Vcomb.fits "$PROJECT_DIR/Vcomb.fits"
chown -R ga:ga "$PROJECT_DIR"

# Compute ground truth from input FITS
python3 << 'PYEOF'
import json, os
from astropy.io import fits
import numpy as np

fpath = "/home/ga/AstroImages/core_isolation/Vcomb.fits"
data = fits.getdata(fpath)
if data.ndim > 2:
    data = data[0]

h, w = data.shape
ch, cw = int(h*0.1), int(w*0.1)
core = data[h//2 - ch//2 : h//2 + ch//2, w//2 - cw//2 : w//2 + cw//2]
edges = np.concatenate([
    data[:ch, :cw].flatten(),
    data[:ch, -cw:].flatten(),
    data[-ch:, :cw].flatten(),
    data[-ch:, -cw:].flatten()
])

gt = {
    "input_mean": float(np.nanmean(data)),
    "input_std": float(np.nanstd(data)),
    "input_core_median": float(np.nanmedian(core)),
    "input_edge_median": float(np.nanmedian(edges)),
    "input_shape": list(data.shape)
}

with open("/tmp/core_isolation_ground_truth.json", "w") as f:
    json.dump(gt, f)
PYEOF

chmod 666 /tmp/core_isolation_ground_truth.json 2>/dev/null || true

# Launch AstroImageJ
launch_astroimagej 120
sleep 2

WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="