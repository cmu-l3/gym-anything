#!/bin/bash
set -euo pipefail

echo "=== Setting up Atmospheric Extinction Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/AstroImages/extinction_data"
MEASURE_DIR="/home/ga/AstroImages/measurements"

# Clean any previous state
rm -rf "$PROJECT_DIR" "$MEASURE_DIR"
mkdir -p "$PROJECT_DIR" "$MEASURE_DIR"

# 1. Extract 15 distributed frames from the cached WASP-12b archive
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ ! -f "$WASP12_CACHE" ]; then
    echo "ERROR: WASP-12b cached data not found at $WASP12_CACHE"
    exit 1
fi

echo "Extracting FITS sequence..."
mkdir -p /tmp/wasp12b_temp
tar -xzf "$WASP12_CACHE" -C /tmp/wasp12b_temp

# Take every 10th frame to get a wide spread of airmass across the night (max 15 frames)
COUNT=0
for f in $(find /tmp/wasp12b_temp -name "*.fits" | sort); do
    if [ $((COUNT % 10)) -eq 0 ]; then
        cp "$f" "$PROJECT_DIR/$(basename "$f")"
    fi
    COUNT=$((COUNT + 1))
    if [ $(ls -1 "$PROJECT_DIR"/*.fits | wc -l) -ge 15 ]; then
        break
    fi
done
rm -rf /tmp/wasp12b_temp

# 2. Use Python to dynamically compute the ground truth extinction coefficient
echo "Computing ground truth slope and generating instructions..."
python3 << 'PYEOF'
import os, glob, json
import numpy as np
from astropy.io import fits
import scipy.ndimage as ndimage
from scipy.stats import linregress

work_dir = "/home/ga/AstroImages/extinction_data"
files = sorted(glob.glob(os.path.join(work_dir, "*.fits")))

if not files:
    print("No FITS files found in extraction!")
    exit(1)

data0 = fits.getdata(files[0])

# Auto-detect a bright but unsaturated comparison star
smoothed = ndimage.gaussian_filter(data0, 2.0)
thresh = np.percentile(smoothed, 99.5)
labeled, num = ndimage.label(smoothed > thresh)
centers = ndimage.center_of_mass(data0, labeled, range(1, num+1))

best_star = (2000, 2000) # Fallback center
best_flux = 0

for cy, cx in centers:
    iy, ix = int(cy), int(cx)
    # Stay away from the edges
    if 200 < iy < data0.shape[0]-200 and 200 < ix < data0.shape[1]-200:
        peak = np.max(data0[iy-2:iy+3, ix-2:ix+3])
        # Bright but safely below non-linear/saturation regimes
        if 10000 < peak < 45000:
            ap = data0[iy-10:iy+11, ix-10:ix+11]
            bg = np.median(data0[iy-20:iy+20, ix-20:ix+20])
            flux = np.sum(ap - bg)
            if flux > best_flux:
                best_flux = flux
                best_star = (cx, cy)

cx, cy = best_star
airmasses = []
mags = []

# Perform baseline photometry across all 15 frames
for f in files:
    d = fits.getdata(f)
    h = fits.getheader(f)
    am = float(h.get('AIRMASS', 1.0))
    
    iy, ix = int(cy), int(cx)
    ap = d[iy-10:iy+11, ix-10:ix+11]
    bg = np.median(d[iy-20:iy+20, ix-20:ix+20])
    flux = np.sum(ap - bg)
    
    if flux > 0:
        airmasses.append(am)
        mags.append(-2.5 * np.log10(flux))

# Compute linear regression slope
if len(airmasses) > 1:
    slope, intercept, r, p, se = linregress(airmasses, mags)
else:
    slope = 0.15 # Fallback

gt = {
    "target_x": round(cx, 1),
    "target_y": round(cy, 1),
    "extinction_coefficient": float(slope),
    "frames_used": len(airmasses)
}

with open('/tmp/extinction_ground_truth.json', 'w') as f:
    json.dump(gt, f)

# Generate Instructions file for the agent
inst = f"""TARGET STAR COORDINATES:
X: {round(cx, 1)}
Y: {round(cy, 1)}

Please perform multi-frame aperture photometry on this star across the 15 FITS files.
Extract the AIRMASS and Source flux for each frame.
Compute the instrumental magnitude using the formula: M = -2.5 * log10(Flux)
Find the linear slope of Instrumental Magnitude (y) vs Airmass (x).
Report the coefficient in ~/AstroImages/measurements/extinction_report.txt
"""

with open('/home/ga/AstroImages/instructions.txt', 'w') as f:
    f.write(inst)
PYEOF

chown -R ga:ga /home/ga/AstroImages

# 3. Start AstroImageJ (agent must load the files manually)
echo "Starting AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 1

# Launch the app
su - ga -c "DISPLAY=:1 /usr/local/bin/aij > /tmp/astroimagej_ga.log 2>&1 &"
sleep 8

# Maximize Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "AstroImageJ" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 4. Save state timestamps
date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="