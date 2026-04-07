#!/bin/bash
echo "=== Setting up Multiband Histogram Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
RAW_DIR="/home/ga/AstroImages/raw"
PROJ_DIR="/home/ga/AstroImages/nebula_project"
MEAS_DIR="/home/ga/AstroImages/measurements"

mkdir -p "$RAW_DIR" "$PROJ_DIR" "$MEAS_DIR"

# Copy the real Eagle Nebula narrowband files from the cached installation directory
# (502nmos.fits, 656nmos.fits, 673nmos.fits)
cp /opt/fits_samples/eagle_nebula/*nmos.fits "$RAW_DIR/" 2>/dev/null || true

# Verify FITS files are present
for f in 502nmos.fits 656nmos.fits 673nmos.fits; do
    if [ ! -f "$RAW_DIR/$f" ]; then
        echo "ERROR: Required file $f is missing from $RAW_DIR"
        exit 1
    fi
done

# Generate dynamic ROI and compute ground truth statistics
echo "Generating dynamic ROI and computing ground truth..."
python3 << 'PYEOF'
import os
import json
import random
import numpy as np
from astropy.io import fits

RAW_DIR = "/home/ga/AstroImages/raw"
PROJ_DIR = "/home/ga/AstroImages/nebula_project"

filters = {
    'OIII': '502nmos.fits',
    'Ha': '656nmos.fits',
    'SII': '673nmos.fits'
}

# The Eagle Nebula FITS files are 1600x1600.
# Generate a randomized ROI that covers a structurally interesting part.
# Keep the box away from the extreme edges to avoid empty space.
x = random.randint(400, 900)
y = random.randint(400, 900)
w = random.randint(150, 300)
h = random.randint(150, 300)

gt = {
    'roi': {'x': x, 'y': y, 'width': w, 'height': h},
    'stats': {}
}

for f_name, f_file in filters.items():
    f_path = os.path.join(RAW_DIR, f_file)
    if os.path.exists(f_path):
        data = fits.getdata(f_path)
        
        # In AstroImageJ (ImageJ), origin is top-left, x is column, y is row.
        # Numpy array indexing is data[y:y+h, x:x+w]
        roi_data = data[y:y+h, x:x+w]
        
        mean_val = float(np.mean(roi_data))
        
        # Simulate AstroImageJ's Mode calculation for 32-bit float images.
        # It creates a 256-bin histogram spanning from the min to max of the selection,
        # and the Mode is the center value of the most populated bin.
        r_min, r_max = np.min(roi_data), np.max(roi_data)
        if r_min == r_max:
            mode_val = float(r_min)
        else:
            hist, bin_edges = np.histogram(roi_data, bins=256, range=(r_min, r_max))
            max_bin = np.argmax(hist)
            mode_val = float((bin_edges[max_bin] + bin_edges[max_bin+1]) / 2.0)
            
        gt['stats'][f_name] = {'mean': mean_val, 'mode': mode_val}
        print(f"Computed {f_name}: Mean={mean_val:.4f}, Mode={mode_val:.4f}")

# Save ground truth for the verifier
with open('/tmp/histogram_ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)

# Write ROI instructions for the agent
inst_path = os.path.join(PROJ_DIR, "roi_instructions.txt")
with open(inst_path, 'w') as f:
    f.write("Target Region of Interest (ROI) for Histogram Analysis:\n")
    f.write("----------------------------------------------------\n")
    f.write(f"X: {x}\n")
    f.write(f"Y: {y}\n")
    f.write(f"Width: {w}\n")
    f.write(f"Height: {h}\n")
    f.write("----------------------------------------------------\n")
    f.write("Apply this exact selection to all three narrowband images\n")
    f.write("and extract the Mean and Mode from the Histogram tool.\n")
PYEOF

# Ensure proper permissions
chown -R ga:ga /home/ga/AstroImages

# Launch AstroImageJ (agent must open the files themselves)
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Maximize the window
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "AstroImageJ window maximized"
fi

# Take initial screenshot showing AstroImageJ ready to be used
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="