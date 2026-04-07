#!/bin/bash
echo "=== Setting up Measure Dust Optical Depth task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
TASK_DIR="/home/ga/AstroImages/optical_depth"
OUT_DIR="$TASK_DIR/output"
rm -rf "$TASK_DIR"
mkdir -p "$TASK_DIR" "$OUT_DIR"

# Copy real Hubble data
cp /opt/fits_samples/eagle_nebula/656nmos.fits "$TASK_DIR/656nmos.fits"

# Calculate ground truth dynamically and generate targets text file
python3 << 'PYEOF'
import json
import os
import numpy as np
from astropy.io import fits

fits_path = "/home/ga/AstroImages/optical_depth/656nmos.fits"
data = fits.getdata(fits_path).astype(float)

# Handle 3D FITS cubes if present
if data.ndim == 3:
    data = data[0]

# Pick appropriate coordinates within the image bounds
shape_y, shape_x = data.shape
pillar_x = int(shape_x * 0.45)
pillar_y = int(shape_y * 0.55)
bg_x = int(shape_x * 0.35)
bg_y = int(shape_y * 0.45)
radius = 10

def get_mean_flux(img, cx, cy, r):
    # Match AstroImageJ's circular aperture calculation behavior
    y, x = np.ogrid[:img.shape[0], :img.shape[1]]
    mask = (x - cx)**2 + (y - cy)**2 <= r**2
    return float(np.mean(img[mask]))

# Calculate ground truth measurements
i_pillar = get_mean_flux(data, pillar_x, pillar_y, radius)
i_bg = get_mean_flux(data, bg_x, bg_y, radius)

if i_bg == 0: i_bg = 1e-6
transmission = i_pillar / i_bg
if transmission <= 0: transmission = 1e-6
optical_depth = -np.log(transmission)

gt = {
    "pillar_x": pillar_x, "pillar_y": pillar_y,
    "bg_x": bg_x, "bg_y": bg_y,
    "radius": radius,
    "i_pillar": i_pillar,
    "i_bg": i_bg,
    "transmission": transmission,
    "optical_depth": optical_depth
}

# Save ground truth for the verifier (hidden from agent)
with open("/tmp/ground_truth.json", "w") as f:
    json.dump(gt, f)

# Create instructions for the agent
with open("/home/ga/AstroImages/optical_depth/measurement_targets.txt", "w") as f:
    f.write(f"Pillar Core: X = {pillar_x}, Y = {pillar_y}, Radius = {radius}\n")
    f.write(f"Background Emission: X = {bg_x}, Y = {bg_y}, Radius = {radius}\n")
PYEOF

# Ensure permissions
chown -R ga:ga "$TASK_DIR"

# Launch AstroImageJ
echo "Launching AstroImageJ..."
if ! pgrep -f "AstroImageJ\|aij" > /dev/null; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh &"
    sleep 10
fi

# Ensure window is maximized
WID=$(DISPLAY=:1 wmctrl -l | grep -i "AstroImageJ\|ImageJ" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Capture initial evidence
take_screenshot /tmp/task_initial.png || true

echo "=== Task setup complete ==="