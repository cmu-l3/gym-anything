#!/bin/bash
set -e

echo "=== Setting up Telescope Drift Measurement Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create project directories
DATA_DIR="/home/ga/AstroImages/tracking_data"
MEASURE_DIR="/home/ga/AstroImages/measurements"
rm -rf "$DATA_DIR" "$MEASURE_DIR"
mkdir -p "$DATA_DIR" "$MEASURE_DIR"

# ============================================================
# Extract and prepare WASP-12b data with mathematically injected drift
# ============================================================
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ ! -f "$WASP12_CACHE" ]; then
    echo "Downloading WASP-12b calibrated images (needed for base frame)..."
    wget -q "https://www.astro.louisville.edu/software/astroimagej/examples/WASP-12b_example_calibrated_images.tar.gz" -O "$WASP12_CACHE" || true
fi

echo "Extracting base frame..."
mkdir -p /tmp/wasp_tmp
tar -xzf "$WASP12_CACHE" -C /tmp/wasp_tmp --wildcards "*.fits" | head -5 || true

# Python script to inject exact sub-pixel drift into a sequence of 50 frames
cat > /tmp/inject_drift.py << 'PYEOF'
import os
import glob
import json
import random
import numpy as np
from astropy.io import fits
from scipy.ndimage import shift

# Find a base FITS file
base_files = glob.glob("/tmp/wasp_tmp/**/*.fits", recursive=True) + glob.glob("/tmp/wasp_tmp/**/*.fit", recursive=True)
if not base_files:
    raise RuntimeError("No FITS files found to act as base frame.")

base_file = base_files[0]
print(f"Using base frame: {base_file}")

data, hdr = fits.getdata(base_file, header=True)

# Crop the center 1024x1024 to make processing fast and fit well on screen
cy, cx = data.shape[0] // 2, data.shape[1] // 2
data = data[cy-512:cy+512, cx-512:cx+512].astype(np.float32)

# Generate randomized ground truth drift (15 to 50 pixels in both axes, random signs)
dx_total = random.uniform(15.0, 50.0) * random.choice([1, -1])
dy_total = random.uniform(15.0, 50.0) * random.choice([1, -1])

num_frames = 50
out_dir = "/home/ga/AstroImages/tracking_data"

print(f"Injecting drift: DX={dx_total:.2f}, DY={dy_total:.2f} over {num_frames} frames")

for i in range(num_frames):
    shift_x = i * dx_total / (num_frames - 1)
    shift_y = i * dy_total / (num_frames - 1)
    
    # Apply bilinear sub-pixel shift
    shifted = shift(data, (shift_y, shift_x), order=1, mode='nearest')
    
    # Add minor noise to avoid frames being bit-for-bit identical
    noise = np.random.normal(0, np.sqrt(np.abs(np.median(data))), shifted.shape)
    shifted = shifted + noise * 0.5
    
    out_path = os.path.join(out_dir, f"frame_{i+1:03d}.fits")
    fits.writeto(out_path, shifted.astype(np.float32), hdr, overwrite=True)

# Save ground truth explicitly for verifier
gt = {
    "num_frames": num_frames,
    "dx_total": dx_total,
    "dy_total": dy_total
}
with open("/tmp/tracking_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)

print("Drift injection complete.")
PYEOF

python3 /tmp/inject_drift.py
rm -rf /tmp/wasp_tmp /tmp/inject_drift.py

chown -R ga:ga "$DATA_DIR" "$MEASURE_DIR"

# ============================================================
# Launch AstroImageJ
# ============================================================
echo "Launching AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 1

# Start AIJ in the background as the GA user
su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh &"
sleep 10

# Wait for window and maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "AstroImageJ\|ImageJ" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any welcome screens
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot to record the starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="