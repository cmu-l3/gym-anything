#!/bin/bash
echo "=== Setting up Cosmic Ray Counting Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AstroImages/cosmic_ray_project"
RESULTS_DIR="$PROJECT_DIR/results"
rm -rf "$PROJECT_DIR"
mkdir -p "$RESULTS_DIR"

# Python script to find two matching dark frames, copy them, and calculate ground truth
python3 << 'PYEOF'
import os
import glob
import json
import shutil
import numpy as np
from astropy.io import fits

LFC_BASE = "/opt/fits_samples/palomar_lfc"
PROJECT_DIR = "/home/ga/AstroImages/cosmic_ray_project"

# 1. Find all FITS files and isolate darks
fits_files = glob.glob(os.path.join(LFC_BASE, "**/*.fits"), recursive=True) + \
             glob.glob(os.path.join(LFC_BASE, "**/*.fit"), recursive=True)

darks_by_exptime = {}

for fpath in fits_files:
    try:
        hdr = fits.getheader(fpath)
        imgtype = hdr.get('IMAGETYP', '').upper().strip()
        if 'DARK' in imgtype:
            exptime = float(hdr.get('EXPTIME', hdr.get('EXPOSURE', 0)))
            if exptime not in darks_by_exptime:
                darks_by_exptime[exptime] = []
            darks_by_exptime[exptime].append(fpath)
    except Exception:
        pass

# 2. Select two dark frames with the same exposure time (preferably a longer exposure to get more CRs)
selected_exptime = None
for exptime in sorted(darks_by_exptime.keys(), reverse=True):
    if len(darks_by_exptime[exptime]) >= 2:
        selected_exptime = exptime
        break

if not selected_exptime:
    print("ERROR: Could not find two dark frames with matching exposure times.")
    # Fallback to just taking any two darks if exact match fails (unlikely in LFC dataset)
    all_darks = [f for sublist in darks_by_exptime.values() for f in sublist]
    if len(all_darks) >= 2:
        selected_files = all_darks[:2]
        selected_exptime = float(fits.getheader(selected_files[0]).get('EXPTIME', 0))
    else:
        raise RuntimeError("Not enough dark frames found.")
else:
    selected_files = darks_by_exptime[selected_exptime][:2]

print(f"Selected 2 dark frames with EXPTIME = {selected_exptime}s")

# 3. Copy to project directory
dest1 = os.path.join(PROJECT_DIR, "dark_frame_1.fits")
dest2 = os.path.join(PROJECT_DIR, "dark_frame_2.fits")
shutil.copy2(selected_files[0], dest1)
shutil.copy2(selected_files[1], dest2)

# 4. Compute ground truth using robust statistics
d1 = fits.getdata(dest1).astype(float)
d2 = fits.getdata(dest2).astype(float)

# Absolute difference
diff = np.abs(d1 - d2)

# Robust statistics (Median Absolute Deviation)
median_val = float(np.median(diff))
mad = np.median(np.abs(diff - median_val))
std_val = float(mad * 1.4826)  # Convert MAD to standard deviation equivalent

if std_val == 0:
    std_val = float(np.std(diff)) # Fallback if MAD is 0

threshold = median_val + 5 * std_val

# Count events (simple pixel thresholding for ground truth)
events_mask = diff > threshold
num_events = int(np.sum(events_mask))

# Calculate rate: events / (pixels * time)
total_pixels = d1.size
hit_rate = num_events / (total_pixels * selected_exptime) if selected_exptime > 0 else 0

ground_truth = {
    "exptime": selected_exptime,
    "width": d1.shape[1],
    "height": d1.shape[0],
    "raw_dark_mean": float(np.mean(d1)),
    "diff_median": median_val,
    "diff_std": std_val,
    "threshold": threshold,
    "num_events": num_events,
    "hit_rate": hit_rate,
    "total_pixels": total_pixels
}

with open("/tmp/cosmic_ray_ground_truth.json", "w") as f:
    json.dump(ground_truth, f, indent=2)

print("Ground truth computed and saved.")
PYEOF

# Create README.txt for the agent
cat > "$PROJECT_DIR/README.txt" << 'EOF'
COSMIC RAY CALCULATION TASK
===========================
Your task is to calculate the cosmic ray hit rate for this CCD camera.

1. Open both dark_frame_1.fits and dark_frame_2.fits.
2. Check the FITS header for the exposure time (EXPTIME).
3. Use Process > Image Calculator to create an absolute difference image: |dark1 - dark2|
4. Measure the median and standard deviation of the difference image.
5. Threshold: 5 standard deviations above the median.
6. Count how many pixels exceed this threshold.
7. Calculate rate: events per pixel per second.

Output requirements:
- Save difference image: results/difference_image.fits
- Save report: results/cosmic_ray_report.txt (Include exposure time, dimensions, median, std dev, threshold, count, and hit rate).
EOF

chown -R ga:ga "$PROJECT_DIR"

# Launch AstroImageJ
launch_astroimagej 120

# Maximize the window
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="