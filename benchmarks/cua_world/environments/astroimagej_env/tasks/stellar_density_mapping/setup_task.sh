#!/bin/bash
echo "=== Setting up Stellar Density Mapping Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AstroImages/cluster_density"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# FITS data source
NGC_DIR="/opt/fits_samples/ngc6652"

# Prepare FITS and compute ground truth
python3 << 'PYEOF'
import os, shutil, glob, json, subprocess
import numpy as np
from astropy.io import fits
from scipy import ndimage

NGC_DIR = "/opt/fits_samples/ngc6652"
WORK_DIR = "/home/ga/AstroImages/cluster_density"

# Ensure FITS files are unzipped
fits_files = glob.glob(os.path.join(NGC_DIR, "**/*.fits"), recursive=True) + \
             glob.glob(os.path.join(NGC_DIR, "**/*.fit"), recursive=True)

if not fits_files:
    print("No FITS files found, attempting to unzip archives...")
    zips = glob.glob(os.path.join(NGC_DIR, "*.zip"))
    for z in zips:
        subprocess.run(["unzip", "-o", z, "-d", NGC_DIR], check=False)
    fits_files = glob.glob(os.path.join(NGC_DIR, "**/*.fits"), recursive=True) + \
                 glob.glob(os.path.join(NGC_DIR, "**/*.fit"), recursive=True)

if not fits_files:
    raise RuntimeError(f"ERROR: No FITS files found in {NGC_DIR}")

# Pick V-band
vband = None
for f in fits_files:
    if '555' in os.path.basename(f).lower():
        vband = f
        break
if not vband:
    vband = fits_files[0]

print(f"Using FITS file: {vband}")
dest = os.path.join(WORK_DIR, "ngc6652_v.fits")
shutil.copy2(vband, dest)

# Compute Ground Truth Dynamical Center
# Simulate Find Maxima and Blur
data = fits.getdata(dest).astype(float)
if data.ndim == 3:
    data = data[0]
elif data.ndim > 3:
    data = data.reshape(-1, data.shape[-1])[:data.shape[-2], :]

# Replace NaN with median
med = np.nanmedian(data)
data = np.where(np.isfinite(data), data, med)

# Mild smooth to reduce hot pixels
smoothed_data = ndimage.median_filter(data, size=3)

# Find local maxima to simulate AstroImageJ "Find Maxima"
from scipy.ndimage import maximum_filter
# Estimate background and prominence
bg = np.percentile(smoothed_data, 10)
std = np.std(smoothed_data)
threshold = bg + 3 * std

local_max = maximum_filter(smoothed_data, size=5) == smoothed_data
peaks = local_max & (smoothed_data > threshold)

# Create single points image
points = np.zeros_like(data)
points[peaks] = 1.0

num_stars = int(np.sum(points))

# Blur with sigma=20
density = ndimage.gaussian_filter(points, sigma=20.0)

# Find peak
peak_y, peak_x = np.unravel_index(np.argmax(density), density.shape)

gt = {
    "num_stars_detected": num_stars,
    "peak_density_x": int(peak_x),
    "peak_density_y": int(peak_y),
    "image_width": data.shape[1],
    "image_height": data.shape[0]
}

with open("/tmp/density_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground Truth: stars={num_stars}, center=({peak_x}, {peak_y})")
PYEOF

chown -R ga:ga "$PROJECT_DIR"
chown ga:ga "/tmp/density_ground_truth.json"

# Launch AstroImageJ
launch_astroimagej 120

# Maximize the AstroImageJ window
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "AstroImageJ window maximized"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="