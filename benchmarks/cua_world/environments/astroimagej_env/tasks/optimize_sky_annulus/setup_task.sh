#!/bin/bash
echo "=== Setting up optimize_sky_annulus task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create clean working directories
rm -rf /home/ga/AstroImages/photometry
rm -rf /home/ga/AstroImages/measurements
mkdir -p /home/ga/AstroImages/photometry
mkdir -p /home/ga/AstroImages/measurements

# Ensure the FITS data is available
if [ -f /opt/fits_samples/m12/Vcomb.fits ]; then
    cp /opt/fits_samples/m12/Vcomb.fits /home/ga/AstroImages/photometry/m12_Vcomb.fits
else
    echo "ERROR: Missing M12 Vcomb.fits data file!"
    exit 1
fi

# Dynamically analyze the image, pick a suitable star, and compute exact ground truth
cat << 'EOF' > /tmp/gen_gt.py
import os, json
import numpy as np
from astropy.io import fits
from scipy import ndimage

image_path = '/home/ga/AstroImages/photometry/m12_Vcomb.fits'
data = fits.getdata(image_path).astype(float)
if data.ndim > 2: 
    data = data[0]

# Detect stars to find a good target
smoothed = ndimage.gaussian_filter(data, sigma=2.0)
threshold = np.percentile(smoothed, 99.0)
labeled, num = ndimage.label(smoothed > threshold)
centroids = ndimage.center_of_mass(data, labeled, range(1, num+1))

best_star = None
best_gt = None
best_diff = -1

for cy, cx in centroids:
    cy, cx = int(round(cy)), int(round(cx))
    
    # Avoid edges
    if cy < 100 or cx < 100 or cy > data.shape[0]-100 or cx > data.shape[1]-100:
        continue

    # Create masks identical to AstroImageJ's circular aperture logic
    y, x = np.ogrid[:data.shape[0], :data.shape[1]]
    r2 = (x - cx)**2 + (y - cy)**2

    source_mask = r2 <= 6**2

    sky_masks = {
        "A": (r2 >= 10**2) & (r2 <= 15**2),
        "B": (r2 >= 10**2) & (r2 <= 25**2),
        "C": (r2 >= 10**2) & (r2 <= 40**2)
    }

    source_sum = np.sum(data[source_mask])
    source_npix = np.sum(source_mask)

    gt = {}
    valid = True
    sky_medians = []
    
    for cfg, mask in sky_masks.items():
        sky_vals = data[mask]
        if len(sky_vals) == 0:
            valid = False
            break
        sky_med = float(np.median(sky_vals))
        net_flux = float(source_sum - sky_med * source_npix)
        gt[cfg] = {'sky_per_pixel': sky_med, 'net_source_flux': net_flux}
        sky_medians.append(sky_med)

    if not valid: 
        continue

    # Identify a star that has clear contamination progression (Sky A < Sky B < Sky C)
    if sky_medians[0] < sky_medians[1] < sky_medians[2]:
        diff = sky_medians[2] - sky_medians[0]
        # Restrict extreme outliers
        if diff > best_diff and diff < 5000:
            best_diff = diff
            best_star = (cx, cy)
            best_gt = gt

if best_star is None:
    # Fallback if detection fails (unlikely)
    best_star = (data.shape[1]//2, data.shape[0]//2)
    best_gt = {
        "A": {"sky_per_pixel": 100.0, "net_source_flux": 5000.0},
        "B": {"sky_per_pixel": 110.0, "net_source_flux": 4000.0},
        "C": {"sky_per_pixel": 120.0, "net_source_flux": 3000.0}
    }

gt_data = {
    'target_x': best_star[0], 
    'target_y': best_star[1], 
    'configs': best_gt
}

with open('/tmp/photometry_ground_truth.json', 'w') as f:
    json.dump(gt_data, f, indent=2)

with open('/home/ga/AstroImages/photometry/target_star.txt', 'w') as f:
    f.write(f"Target Star Coordinates:\nX: {best_star[0]}\nY: {best_star[1]}\n")
EOF

python3 /tmp/gen_gt.py

# Fix permissions
chown -R ga:ga /home/ga/AstroImages
chmod 644 /tmp/photometry_ground_truth.json

# Launch AstroImageJ
launch_astroimagej 60

# Ensure window is visible and maximized
sleep 5
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial snapshot
take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="