#!/bin/bash
echo "=== Setting up UV Star Formation Census Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create project directories
mkdir -p /home/ga/AstroImages/uv_census
mkdir -p /home/ga/AstroImages/measurements

# Copy FITS file from pre-cached sample location
if [ -f /opt/fits_samples/uit_galaxy_sample.fits ]; then
    cp /opt/fits_samples/uit_galaxy_sample.fits /home/ga/AstroImages/uv_census/uit_galaxy.fits
else
    echo "ERROR: uit_galaxy_sample.fits not found."
    exit 1
fi
chown -R ga:ga /home/ga/AstroImages

# Dynamically generate Ground Truth using Python/SciPy directly from the actual FITS data
python3 << 'PYEOF'
import os
import json
import numpy as np
from astropy.io import fits
from scipy.ndimage import gaussian_filter, label

fits_file = "/home/ga/AstroImages/uv_census/uit_galaxy.fits"
data = fits.getdata(fits_file).astype(float)

# Handle potential 3D arrays
if data.ndim == 3:
    data = data[0]

# Agent is instructed to create ROI at X=0, Y=0, W=50, H=50 (ImageJ coords)
# In numpy, this corresponds to data[0:50, 0:50]
roi = data[0:50, 0:50]
bg_mean = float(np.mean(roi))
bg_std = float(np.std(roi, ddof=1)) # ImageJ typically uses sample standard deviation (N-1)

# Calculate threshold: Mean + 3*StdDev
threshold = bg_mean + 3 * bg_std

# Apply Gaussian Blur (sigma=2.0)
smoothed = gaussian_filter(data, sigma=2.0, mode='nearest')

# Apply threshold
binary = smoothed >= threshold

# Particle analysis (size >= 5)
struct = np.ones((3,3), dtype=int) # 8-connected component labeling
labeled, num_features = label(binary, structure=struct)

total_knots = 0
total_area = 0

for i in range(1, num_features + 1):
    area = np.sum(labeled == i)
    if area >= 5:
        total_knots += 1
        total_area += area

gt = {
    "bg_mean": bg_mean,
    "bg_std": bg_std,
    "threshold": threshold,
    "total_knots": total_knots,
    "total_area": float(total_area)
}

with open("/tmp/uv_census_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground Truth Generated: {total_knots} knots, {total_area} pixels area.")
PYEOF
chmod 644 /tmp/uv_census_ground_truth.json

# Launch AstroImageJ (do not load the image, agent must do it)
launch_astroimagej 120

# Maximize the AstroImageJ window for better agent visibility
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot to record starting state
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="