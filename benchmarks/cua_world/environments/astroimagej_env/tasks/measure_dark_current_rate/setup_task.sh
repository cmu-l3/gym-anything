#!/bin/bash
echo "=== Setting up Measure CCD Dark Current Rate Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AstroImages/dark_current"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"/{bias,dark,results}

# Ensure LFC sample data exists
LFC_BASE="/opt/fits_samples/palomar_lfc"
if [ ! -d "$LFC_BASE" ]; then
    echo "Extracting Palomar LFC archive..."
    if [ -f "/opt/fits_samples/palomar_lfc.tar.bz2" ]; then
        mkdir -p "$LFC_BASE"
        tar -xjf /opt/fits_samples/palomar_lfc.tar.bz2 -C "$LFC_BASE"
    else
        echo "ERROR: Palomar LFC data missing. Task cannot proceed."
        exit 1
    fi
fi

# Use Python to select frames and generate dynamic ground truth
python3 << 'PYEOF'
import os, shutil, json, glob
from astropy.io import fits
import numpy as np

LFC_BASE = "/opt/fits_samples/palomar_lfc"
WORK_DIR = "/home/ga/AstroImages/dark_current"
GAIN = 2.0  # e-/ADU

fits_files = glob.glob(os.path.join(LFC_BASE, "**/*.fit*"), recursive=True)

bias_files = []
dark_files = []

# Classify
for f in sorted(fits_files):
    try:
        hdr = fits.getheader(f)
        imgtype = hdr.get('IMAGETYP', '').upper()
        if 'BIAS' in imgtype:
            bias_files.append(f)
        elif 'DARK' in imgtype:
            dark_files.append(f)
    except:
        pass

# Select up to 5 of each
bias_sel = bias_files[:5]
dark_sel = dark_files[:5]

# Copy to working dir
for i, f in enumerate(bias_sel):
    shutil.copy2(f, os.path.join(WORK_DIR, 'bias', f'bias_{i+1:02d}.fits'))
    
for i, f in enumerate(dark_sel):
    shutil.copy2(f, os.path.join(WORK_DIR, 'dark', f'dark_{i+1:02d}.fits'))

# Compute ground truth
gt = {
    "bias_count": len(bias_sel),
    "dark_count": len(dark_sel),
}

if bias_sel and dark_sel:
    bias_data = np.array([fits.getdata(f).astype(float) for f in bias_sel])
    dark_data = np.array([fits.getdata(f).astype(float) for f in dark_sel])
    
    master_bias = np.median(bias_data, axis=0)
    master_dark = np.median(dark_data, axis=0)
    
    gt["bias_median"] = float(np.median(master_bias))
    gt["dark_median"] = float(np.median(master_dark))
    
    hdr = fits.getheader(dark_sel[0])
    exptime = float(hdr.get('EXPTIME', hdr.get('EXPOSURE', 1.0)))
    gt["exptime"] = exptime
    
    # Calculate expected dark rate
    gt["dark_rate"] = ((gt["dark_median"] - gt["bias_median"]) * GAIN) / exptime
    
    print(f"Ground Truth Computed:")
    print(f"Bias Median: {gt['bias_median']:.2f} ADU")
    print(f"Dark Median: {gt['dark_median']:.2f} ADU")
    print(f"Exptime: {gt['exptime']} s")
    print(f"Rate: {gt['dark_rate']:.4f} e-/pix/sec")

with open("/tmp/dark_current_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)
PYEOF

chown -R ga:ga "$PROJECT_DIR"
chmod 777 /tmp/dark_current_ground_truth.json

# Launch AstroImageJ
launch_astroimagej 120

# Maximize AIJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="