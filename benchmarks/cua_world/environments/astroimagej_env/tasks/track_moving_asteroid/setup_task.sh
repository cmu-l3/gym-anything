#!/bin/bash
set -euo pipefail

echo "=== Setting up track_moving_asteroid task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create necessary directories
sudo -u ga mkdir -p /home/ga/AstroImages/raw/asteroid_sequence
sudo -u ga mkdir -p /home/ga/AstroImages/measurements
mkdir -p /var/lib/app/ground_truth

# Generate the test dataset using real HST data as a base
# We inject a moving PSF to simulate an asteroid moving across a real star field
echo "Preparing image sequence..."
cat << 'EOF' > /tmp/prep_data.py
import os
import json
import numpy as np
from astropy.io import fits

out_dir = "/home/ga/AstroImages/raw/asteroid_sequence"
os.makedirs(out_dir, exist_ok=True)

# Try to use a real FITS file from the environment to provide realistic background/noise
base_file = "/opt/fits_samples/hst_wfpc2_sample.fits"
data = None

try:
    if os.path.exists(base_file):
        with fits.open(base_file) as hdul:
            for hdu in hdul:
                if hdu.data is not None and len(hdu.data.shape) >= 2:
                    data = hdu.data
                    break
except Exception as e:
    print(f"Could not load HST sample: {e}")

# Fallback if real image is unavailable or unreadable
if data is None:
    print("Using generated background as fallback")
    data = np.random.normal(100, 15, (800, 800)).astype(np.float32)

# Ensure 2D and crop a 600x600 region
if len(data.shape) > 2:
    data = data[0]
h, w = data.shape
if h > 600 and w > 600:
    data = data[100:700, 100:700]
else:
    # Pad if too small
    padded = np.ones((600, 600), dtype=np.float32) * np.nanmedian(data)
    ph, pw = min(h, 600), min(w, 600)
    padded[0:ph, 0:pw] = data[0:ph, 0:pw]
    data = padded

data = data.astype(np.float32)

# Function to inject a realistic star/asteroid PSF
def add_psf(img, x, y, flux):
    yy, xx = np.mgrid[0:img.shape[0], 0:img.shape[1]]
    # Gaussian PSF, sigma=2.0
    r2 = (xx - x)**2 + (yy - y)**2
    star = flux * np.exp(-r2 / (2 * 2.0**2))
    return img + star

# Trajectory for the asteroid
start_x, start_y = 150.5, 200.5
end_x, end_y = 170.5, 220.5
frames = 5
flux = np.nanmax(data) * 0.8  # Make it bright but realistic

for i in range(frames):
    fraction = i / (frames - 1)
    cx = start_x + fraction * (end_x - start_x)
    cy = start_y + fraction * (end_y - start_y)
    
    frame_data = add_psf(data.copy(), cx, cy, flux)
    
    # Add slight per-frame poisson-like noise variation
    noise = np.random.normal(0, np.nanstd(data) * 0.05, frame_data.shape)
    frame_data += noise
    
    hdu = fits.PrimaryHDU(frame_data)
    # Add minimal headers
    hdu.header['OBJECT'] = 'Asteroid Field'
    hdu.header['EXPTIME'] = 30.0
    filepath = os.path.join(out_dir, f"frame_{i+1:02d}.fits")
    hdu.writeto(filepath, overwrite=True)

# Save ground truth for the verifier
gt = {
    "slice1_x": float(start_x),
    "slice1_y": float(start_y),
    "slice5_x": float(end_x),
    "slice5_y": float(end_y),
    "tolerance": 4.0
}
with open("/var/lib/app/ground_truth/asteroid_gt.json", "w") as f:
    json.dump(gt, f)
print("Data preparation complete.")
EOF

python3 /tmp/prep_data.py
chown -R ga:ga /home/ga/AstroImages/raw/asteroid_sequence

# Start AstroImageJ cleanly
echo "Starting AstroImageJ..."
if ! pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/aij > /tmp/aij_task.log 2>&1 &"
    
    # Wait for application window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ"; then
            echo "AstroImageJ window detected."
            break
        fi
        sleep 1
    done
fi

# Ensure window is visible and focused
WID=$(DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot as proof of setup
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="