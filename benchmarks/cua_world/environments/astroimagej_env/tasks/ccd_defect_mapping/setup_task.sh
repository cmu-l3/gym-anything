#!/bin/bash
echo "=== Setting up CCD Defect Mapping Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AstroImages/defect_mapping"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/darks" "$PROJECT_DIR/flats"

# Use python to extract and organize the specific frames we need from the cached real data
# and pre-compute ground truth statistics
python3 << 'PYEOF'
import os, shutil, glob, json
from astropy.io import fits
import numpy as np

LFC_BASE = "/opt/fits_samples/palomar_lfc"
WORK_DIR = "/home/ga/AstroImages/defect_mapping"
DARK_DIR = os.path.join(WORK_DIR, "darks")
FLAT_DIR = os.path.join(WORK_DIR, "flats")

# Discover FITS files
fits_files = []
for root, dirs, files in os.walk(LFC_BASE):
    for f in files:
        if f.lower().endswith(('.fits', '.fit')):
            fits_files.append(os.path.join(root, f))

print(f"Found {len(fits_files)} total FITS files in {LFC_BASE}")

darks = []
flats = []

# Classify files
for fpath in sorted(fits_files):
    try:
        hdr = fits.getheader(fpath)
        imgtype = hdr.get('IMAGETYP', '').upper().strip()
        if 'DARK' in imgtype:
            darks.append(fpath)
        elif 'FLAT' in imgtype:
            flats.append(fpath)
    except Exception as e:
        print(f"Skipping {fpath}: {e}")

# Limit to 10 frames each to make the task performant for the agent, but still statistically valid
darks = darks[:10]
flats = flats[:10]

# Copy to working directory
for i, f in enumerate(darks):
    shutil.copy2(f, os.path.join(DARK_DIR, f"dark_{i+1:02d}.fits"))
for i, f in enumerate(flats):
    shutil.copy2(f, os.path.join(FLAT_DIR, f"flat_{i+1:02d}.fits"))

print(f"Prepared {len(darks)} darks and {len(flats)} flats")

# --- COMPUTE GROUND TRUTH ---
gt = {}

if darks and flats:
    # Process Darks
    print("Computing master dark ground truth...")
    dark_data = [fits.getdata(f).astype(float) for f in darks]
    master_dark = np.median(dark_data, axis=0)
    
    gt['master_dark_median'] = float(np.median(master_dark))
    gt['master_dark_stddev'] = float(np.std(master_dark))
    
    gt['hot_pixel_threshold'] = gt['master_dark_median'] + 5 * gt['master_dark_stddev']
    gt['hot_pixel_count'] = int(np.sum(master_dark > gt['hot_pixel_threshold']))
    
    # Process Flats
    print("Computing master flat ground truth...")
    flat_data = [fits.getdata(f).astype(float) for f in flats]
    master_flat = np.median(flat_data, axis=0)
    
    gt['master_flat_median'] = float(np.median(master_flat))
    
    gt['dead_pixel_threshold'] = 0.5 * gt['master_flat_median']
    gt['dead_pixel_count'] = int(np.sum(master_flat < gt['dead_pixel_threshold']))
    
    # Global metrics
    gt['total_pixels'] = int(master_dark.size)
    gt['defect_fraction'] = float(gt['hot_pixel_count'] + gt['dead_pixel_count']) / gt['total_pixels']
    
    print(f"Ground Truth Computed:")
    print(f"  Dark Med: {gt['master_dark_median']:.2f}, Std: {gt['master_dark_stddev']:.2f}")
    print(f"  Hot Count: {gt['hot_pixel_count']}")
    print(f"  Flat Med: {gt['master_flat_median']:.2f}")
    print(f"  Dead Count: {gt['dead_pixel_count']}")
    
    with open('/tmp/defect_ground_truth.json', 'w') as f:
        json.dump(gt, f, indent=4)
else:
    print("ERROR: Missing data for ground truth computation")
PYEOF

chown -R ga:ga "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"

# Ensure AstroImageJ is running
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize the AstroImageJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="