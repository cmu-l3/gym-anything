#!/bin/bash
echo "=== Setting up Color Ratio Map Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create directories
WORK_DIR="/home/ga/AstroImages/color_map"
OUT_DIR="$WORK_DIR/output"

rm -rf "$WORK_DIR" 2>/dev/null || true
mkdir -p "$OUT_DIR"
chown -R ga:ga "$WORK_DIR"

# Copy images
echo "Copying real VLT images..."
cp /opt/fits_samples/m12/Bcomb.fits "$WORK_DIR/" 2>/dev/null || true
cp /opt/fits_samples/m12/Vcomb.fits "$WORK_DIR/" 2>/dev/null || true

# Fallback: Download if not present
if [ ! -f "$WORK_DIR/Bcomb.fits" ] || [ ! -f "$WORK_DIR/Vcomb.fits" ]; then
    echo "FITS files not found locally, downloading from ESA Hubble..."
    wget -q "https://esahubble.org/static/projects/fits_liberator/datasets/m12/Bcomb.zip" -O /tmp/Bcomb.zip
    unzip -o -j /tmp/Bcomb.zip -d "$WORK_DIR/" 2>/dev/null || true
    wget -q "https://esahubble.org/static/projects/fits_liberator/datasets/m12/Vcomb.zip" -O /tmp/Vcomb.zip
    unzip -o -j /tmp/Vcomb.zip -d "$WORK_DIR/" 2>/dev/null || true
fi

# Generate ground truth and target_stars.txt dynamically based on the actual FITS data
echo "Computing ground truth properties..."
python3 << 'PYEOF'
import os
import json
import numpy as np
import random
try:
    from astropy.io import fits
    from scipy import ndimage
except ImportError:
    import sys
    sys.exit(0)

WORK_DIR = "/home/ga/AstroImages/color_map"
B_path = os.path.join(WORK_DIR, "Bcomb.fits")
V_path = os.path.join(WORK_DIR, "Vcomb.fits")

if not os.path.exists(B_path) or not os.path.exists(V_path):
    sys.exit(0)

B_data = fits.getdata(B_path).astype(float)
V_data = fits.getdata(V_path).astype(float)

if B_data.ndim == 3: B_data = B_data[0]
if V_data.ndim == 3: V_data = V_data[0]

V_safe = np.where(V_data <= 0, np.nan, V_data)
ratio = B_data / V_safe

# Find target stars dynamically
smoothed = ndimage.gaussian_filter(V_data, 2.0)
thresh = np.nanpercentile(smoothed, 99.5)
labeled, num = ndimage.label(smoothed > thresh)
centers = ndimage.center_of_mass(V_data, labeled, range(1, min(num+1, 100)))

stars = []
for cy, cx in centers:
    y, x = int(cy), int(cx)
    if 20 < y < V_data.shape[0]-20 and 20 < x < V_data.shape[1]-20:
        b_val = np.nanmean(B_data[y-1:y+2, x-1:x+2])
        v_val = np.nanmean(V_data[y-1:y+2, x-1:x+2])
        if v_val > 0 and b_val > 0:
            stars.append({'x': x, 'y': y, 'v': v_val, 'bv': float(b_val/v_val)})

stars.sort(key=lambda s: s['bv'])
if len(stars) < 3:
    # Fallback coordinates if detection fails
    star_red = {'x': 100, 'y': 100, 'bv': 0.5}
    star_mid = {'x': 200, 'y': 200, 'bv': 1.0}
    star_blue = {'x': 300, 'y': 300, 'bv': 2.0}
else:
    star_red = stars[len(stars)//10]
    star_mid = stars[len(stars)//2]
    star_blue = stars[-len(stars)//10]

selected = [star_red, star_mid, star_blue]
random.shuffle(selected)
labels = ['Star_A', 'Star_B', 'Star_C']

target_txt = "Target Stars for B/V Measurement\n(Coordinates are approximate, measure at the brightest pixel near these locations):\n\n"
gt_stars = {}
for i in range(3):
    target_txt += f"{labels[i]}: x={selected[i]['x']}, y={selected[i]['y']}\n"
    gt_stars[labels[i]] = selected[i]['bv']

bluest = max(labels, key=lambda k: gt_stars[k])
reddest = min(labels, key=lambda k: gt_stars[k])

gt = {
    'shape': list(ratio.shape),
    'median_ratio': float(np.nanmedian(ratio)),
    'stars': gt_stars,
    'bluest': bluest,
    'reddest': reddest
}

with open('/tmp/color_ratio_ground_truth.json', 'w') as f:
    json.dump(gt, f)

with open(os.path.join(WORK_DIR, 'target_stars.txt'), 'w') as f:
    f.write(target_txt)
PYEOF

chown -R ga:ga "$WORK_DIR"
chown ga:ga /tmp/color_ratio_ground_truth.json 2>/dev/null || true

# Launch AstroImageJ
echo "Launching AstroImageJ..."
su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh" &
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ImageJ\|AstroImageJ"; then
        break
    fi
    sleep 1
done

# Focus and maximize
DISPLAY=:1 wmctrl -r "AstroImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "AstroImageJ" 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="