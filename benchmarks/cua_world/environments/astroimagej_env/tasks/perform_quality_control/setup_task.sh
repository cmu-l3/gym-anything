#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Quality Control Task ==="

# Record timestamp to prevent gaming (creating the file before the task)
date +%s > /tmp/task_start_timestamp

PROJECT_DIR="/home/ga/AstroImages/quality_control"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Check for cached dataset
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ ! -f "$WASP12_CACHE" ]; then
    echo "ERROR: WASP-12b data not found at $WASP12_CACHE"
    exit 1
fi

echo "Extracting WASP-12b calibrated images..."
TMP_DIR="/tmp/wasp12b_tmp"
mkdir -p "$TMP_DIR"
tar -xzf "$WASP12_CACHE" -C "$TMP_DIR" 2>&1

echo "Selecting and preparing 25 frames with fault injection..."
python3 << 'PYEOF'
import os, glob, shutil, json
import numpy as np
from astropy.io import fits
from scipy.ndimage import gaussian_filter

TMP_DIR = "/tmp/wasp12b_tmp"
PROJECT_DIR = "/home/ga/AstroImages/quality_control"

fits_files = sorted(glob.glob(os.path.join(TMP_DIR, "**/*.fits"), recursive=True) +
                    glob.glob(os.path.join(TMP_DIR, "**/*.fit"), recursive=True))

if len(fits_files) < 25:
    raise RuntimeError("Not enough FITS files found.")

selected_files = fits_files[:25]
degraded_files = []

for i, f in enumerate(selected_files):
    dest = os.path.join(PROJECT_DIR, f"frame_{i+1:03d}.fits")
    
    with fits.open(f) as hdul:
        data = hdul[0].data.astype(np.float32)
        header = hdul[0].header
        
        # Inject realistic faults into specific frames
        if i == 5:  # Frame 06 - Cloud/Transparency drop
            data = data * 0.4
            degraded_files.append(os.path.basename(dest))
        elif i == 13: # Frame 14 - Wind shake (asymmetric motion blur)
            data = gaussian_filter(data, sigma=[1.0, 4.0])
            degraded_files.append(os.path.basename(dest))
        elif i == 20: # Frame 21 - Defocus (symmetric blur)
            data = gaussian_filter(data, sigma=2.5)
            degraded_files.append(os.path.basename(dest))
            
        fits.writeto(dest, data, header, overwrite=True)

gt = {
    "total_frames": 25,
    "bad_frames": degraded_files
}
with open("/tmp/qc_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)

print("Fault injection complete. Degraded frames:", degraded_files)
PYEOF

rm -rf "$TMP_DIR"
chown -R ga:ga "$PROJECT_DIR"
chmod 644 /tmp/qc_ground_truth.json

# Remove any old report file
rm -f /home/ga/Desktop/bad_frames.txt

# Launch AstroImageJ
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

AIJ_PATH=""
for path in "/usr/local/bin/aij" "/opt/astroimagej/astroimagej/bin/AstroImageJ" "/opt/astroimagej/AstroImageJ/bin/AstroImageJ"; do
    if [ -x "$path" ]; then
        AIJ_PATH="$path"
        break
    fi
done

if [ -n "$AIJ_PATH" ]; then
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$AIJ_PATH' > /tmp/astroimagej_ga.log 2>&1" &
    sleep 10
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "AstroImageJ" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="