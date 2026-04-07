#!/bin/bash
echo "=== Setting up CCD Read Noise Characterization task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
WORK_DIR="/home/ga/AstroImages/ccd_characterization"
MEASURE_DIR="/home/ga/AstroImages/measurements"
rm -rf "$WORK_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR"
mkdir -p "$MEASURE_DIR"
mkdir -p "/home/ga/Desktop"

# Use a Python script to find 5 real bias frames, copy them, and compute the ground truth
python3 << 'PYEOF'
import os
import shutil
import json
import numpy as np
import glob
from astropy.io import fits

LFC_BASE = "/opt/fits_samples/palomar_lfc"
WORK_DIR = "/home/ga/AstroImages/ccd_characterization"
GT_FILE = "/tmp/ccd_ground_truth.json"

# Find all FITS files
fits_files = []
for root, dirs, files in os.walk(LFC_BASE):
    for f in files:
        if f.lower().endswith(('.fits', '.fit')):
            fits_files.append(os.path.join(root, f))

print(f"Searching {len(fits_files)} FITS files for bias frames...")

# Filter for BIAS frames
bias_files = []
for f in sorted(fits_files):
    try:
        hdr = fits.getheader(f)
        if 'BIAS' in hdr.get('IMAGETYP', '').upper():
            bias_files.append(f)
            if len(bias_files) >= 5:
                break
    except Exception:
        pass

if len(bias_files) < 2:
    print("WARNING: Could not find enough explicit bias frames. Falling back to the first few FITS files.")
    bias_files = fits_files[:5]

# Copy files to working directory
copied_files = []
for i, src in enumerate(bias_files[:5]):
    dest = os.path.join(WORK_DIR, f"bias_{i+1:03d}.fits")
    shutil.copy2(src, dest)
    copied_files.append(dest)
    print(f"Copied {src} to {dest}")

# Compute Ground Truth
if len(copied_files) >= 2:
    try:
        # Load data as float to prevent integer overflow during subtraction
        data_arrays = [fits.getdata(f).astype(float) for f in copied_files]
        
        # 1. Bias Level = Mean of all pixel means across the individual frames
        frame_means = [np.mean(d) for d in data_arrays]
        bias_level = float(np.median(frame_means))
        
        # 2. Read Noise = std(frameA - frameB) / sqrt(2)
        stddevs = []
        for i in range(len(data_arrays) - 1):
            diff = data_arrays[i] - data_arrays[i+1]
            stddevs.append(np.std(diff))
            
        mean_stddev = float(np.mean(stddevs))
        read_noise = mean_stddev / np.sqrt(2)
        
        gt = {
            "bias_level_adu": bias_level,
            "read_noise_adu": read_noise,
            "stddev_difference": mean_stddev,
            "n_frames_used": len(copied_files),
            "frame_means": frame_means,
            "individual_stddevs": [float(s) for s in stddevs]
        }
        
        with open(GT_FILE, 'w') as f:
            json.dump(gt, f, indent=2)
            
        print(f"Ground Truth Computed:")
        print(f"  Bias Level: {bias_level:.2f} ADU")
        print(f"  StdDev Diff: {mean_stddev:.2f} ADU")
        print(f"  Read Noise: {read_noise:.2f} e-/ADU")
        
    except Exception as e:
        print(f"Error computing ground truth: {e}")
        # Write dummy GT so verifier doesn't crash, but it won't pass
        with open(GT_FILE, 'w') as f:
            json.dump({"error": str(e)}, f)

PYEOF

# Ensure proper ownership
chown -R ga:ga "$WORK_DIR"
chown -R ga:ga "$MEASURE_DIR"

# Write instructions to desktop
cat > /home/ga/Desktop/ccd_task_instructions.txt << 'EOF'
CCD READ NOISE CHARACTERIZATION TASK

1. Open at least 2 bias frames from ~/AstroImages/ccd_characterization/
2. Use Process > Image Calculator to subtract one from the other
3. Measure the Standard Deviation of the difference image
4. Measure the Mean of a single, unsubtracted bias frame
5. Calculate Read Noise = StdDev(Difference) / sqrt(2)
6. Save exactly to: ~/AstroImages/measurements/ccd_read_noise.txt

Format must be:
bias_level_adu = <value>
read_noise_adu = <value>
stddev_difference = <value>
EOF
chown ga:ga /home/ga/Desktop/ccd_task_instructions.txt

# Launch AstroImageJ
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize Window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="