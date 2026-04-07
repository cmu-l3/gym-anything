#!/bin/bash
echo "=== Setting up Aperture Growth Curve Task ==="

# Source utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Create directories
WORK_DIR="/home/ga/AstroImages/growth_curve"
MEAS_DIR="/home/ga/AstroImages/measurements"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$MEAS_DIR"

# Ensure FITS file exists
SRC_IMG="/opt/fits_samples/m12/Vcomb.fits"
DEST_IMG="$WORK_DIR/m12_vband.fits"

if [ ! -f "$SRC_IMG" ]; then
    echo "Source image not found in cache. Attempting to download/extract..."
    mkdir -p /opt/fits_samples/m12
    if [ ! -f "/opt/fits_samples/m12/Vcomb.zip" ]; then
        wget -q --timeout=60 "https://esahubble.org/static/projects/fits_liberator/datasets/m12/Vcomb.zip" -O /opt/fits_samples/m12/Vcomb.zip || true
    fi
    if [ -f "/opt/fits_samples/m12/Vcomb.zip" ]; then
        unzip -q /opt/fits_samples/m12/Vcomb.zip -d /opt/fits_samples/m12/ || true
    fi
fi

# Fallback to sample if M12 is completely unavailable
if [ ! -f "$SRC_IMG" ]; then
    echo "WARNING: Vcomb.fits not found. Falling back to HST sample."
    SRC_IMG="/opt/fits_samples/hst_wfpc2_sample.fits"
fi

cp "$SRC_IMG" "$DEST_IMG" 2>/dev/null || true
chown -R ga:ga "$WORK_DIR" "$MEAS_DIR"

# Python script to generate ground truth and target_star.txt
python3 << 'PYEOF'
import os, json, math
import numpy as np

try:
    from astropy.io import fits
    from scipy import ndimage
    
    img_path = "/home/ga/AstroImages/growth_curve/m12_vband.fits"
    data = fits.getdata(img_path).astype(float)
    if data.ndim == 3:
        data = data[0]

    # Replace NaNs
    med = np.nanmedian(data)
    data = np.where(np.isfinite(data), data, med)

    # Find stars
    smoothed = ndimage.gaussian_filter(data, sigma=2.0)
    threshold = np.percentile(smoothed, 99.5)
    binary = smoothed > threshold
    labeled, num_features = ndimage.label(binary)

    centroids = ndimage.center_of_mass(data, labeled, range(1, min(num_features+1, 500)))

    # Find an isolated star
    best_star = None
    best_flux = 0
    for cy, cx in centroids:
        iy, ix = int(round(cy)), int(round(cx))
        if 100 < iy < data.shape[0]-100 and 100 < ix < data.shape[1]-100:
            # Check isolation: no other centroids within 60 pixels
            isolated = True
            for oy, ox in centroids:
                if (oy, ox) != (cy, cx):
                    if math.hypot(oy-cy, ox-cx) < 60:
                        isolated = False
                        break
            if isolated:
                # Measure rough flux
                flux = np.sum(data[iy-5:iy+6, ix-5:ix+6]) - np.median(data[iy-20:iy+20, ix-20:ix+20])*121
                if 5000 < flux < 80000:
                    if flux > best_flux:
                        best_flux = flux
                        best_star = (cx, cy)

    if not best_star:
        # Fallback
        best_star = (data.shape[1]//2, data.shape[0]//2)

    cx, cy = best_star

    # Calculate ground truth growth curve
    radii = [5, 8, 12, 16, 20, 25, 30]
    gt_fluxes = {}

    y, x = np.ogrid[:data.shape[0], :data.shape[1]]
    dist_sq = (x - cx)**2 + (y - cy)**2

    # Sky annulus
    sky_mask = (dist_sq >= 35**2) & (dist_sq <= 50**2)
    sky_median = float(np.median(data[sky_mask]))

    for r in radii:
        ap_mask = dist_sq <= r**2
        ap_area = int(np.sum(ap_mask))
        flux = float(np.sum(data[ap_mask])) - sky_median * ap_area
        gt_fluxes[str(r)] = float(flux)

    gt = {
        'target_x': float(cx),
        'target_y': float(cy),
        'fluxes': gt_fluxes,
        'sky_median': sky_median
    }

except Exception as e:
    # Fallback if astropy/scipy fails
    cx, cy = 400.0, 400.0
    gt = {
        'target_x': cx,
        'target_y': cy,
        'fluxes': {'5': 1000, '8': 2000, '12': 2500, '16': 2800, '20': 2900, '25': 2950, '30': 2980},
        'error': str(e)
    }

# Create target_star.txt
with open('/home/ga/AstroImages/growth_curve/target_star.txt', 'w') as f:
    f.write(f"Target Star Coordinates for Growth Curve\n")
    f.write(f"X (pixel): {cx:.1f}\n")
    f.write(f"Y (pixel): {cy:.1f}\n")

with open('/tmp/growth_curve_ground_truth.json', 'w') as f:
    json.dump(gt, f)
PYEOF

chown ga:ga /home/ga/AstroImages/growth_curve/target_star.txt

# Launch AstroImageJ
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

AIJ_PATH=""
for path in \
    "/usr/local/bin/aij" \
    "/opt/astroimagej/astroimagej/bin/AstroImageJ" \
    "/opt/astroimagej/AstroImageJ/bin/AstroImageJ"; do
    if [ -x "$path" ]; then
        AIJ_PATH="$path"
        break
    fi
done

if [ -n "$AIJ_PATH" ]; then
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$AIJ_PATH' > /tmp/aij.log 2>&1 &"
    sleep 5
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "ImageJ\|AstroImageJ"; then
            break
        fi
        sleep 1
    done
    
    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_screenshot.png 2>/dev/null || true

echo "=== Task Setup Complete ==="