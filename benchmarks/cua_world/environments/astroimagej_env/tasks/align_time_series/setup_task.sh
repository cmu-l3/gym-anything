#!/bin/bash
set -euo pipefail

echo "=== Setting up align_time_series task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
sudo -u ga mkdir -p /home/ga/AstroImages/raw/time_series
sudo -u ga mkdir -p /home/ga/AstroImages/processed

# Clean up any previous attempts
sudo -u ga rm -f /home/ga/AstroImages/raw/time_series/*.fits
sudo -u ga rm -f /home/ga/AstroImages/processed/aligned_stack.fits

echo "Generating time-series data with precise tracking drift..."

# Create Python script to generate drifting frames from real data
cat > /tmp/prepare_drifting_frames.py << 'EOF'
import os
import sys
import numpy as np
from astropy.io import fits
from scipy.ndimage import shift

input_file = "/opt/fits_samples/m12/Vcomb.fits"
out_dir = "/home/ga/AstroImages/raw/time_series"

# Load real M12 V-band observation
if os.path.exists(input_file):
    print(f"Loading real starfield from {input_file}")
    with fits.open(input_file) as hdul:
        base_data = hdul[0].data.astype(float)
        # Crop center to keep processing fast and files manageable
        h, w = base_data.shape
        cy, cx = h//2, w//2
        base_data = base_data[cy-400:cy+400, cx-400:cx+400]
else:
    print("WARNING: Real FITS missing. Generating synthetic starfield fallback.")
    base_data = np.random.normal(100, 10, (800, 800))
    for _ in range(80):
        x, y = np.random.randint(50, 750, 2)
        base_data[y-2:y+3, x-2:x+3] += 800

# Generate 10 frames with strict drift: dy=-2.0, dx=+3.5 per frame
for i in range(10):
    dy = -2.0 * i
    dx = 3.5 * i
    
    # Apply spatial shift (drift)
    shifted = shift(base_data, shift=(dy, dx), order=1)
    
    # Add varying Poisson/Gaussian noise to ensure frames are not perfect clones
    # (prevents cheating by simply duplicating frame_01 10 times)
    noise = np.random.normal(0, 8.0, shifted.shape)
    final_frame = shifted + noise
    
    # Save frame
    out_path = os.path.join(out_dir, f"frame_{i+1:02d}.fits")
    hdu = fits.PrimaryHDU(final_frame.astype(np.float32))
    hdu.header['FRAME'] = i + 1
    hdu.header['EXPTIME'] = 30.0
    hdu.header['OBJECT'] = 'Time Series Target'
    hdu.writeto(out_path, overwrite=True)
    print(f"Generated {os.path.basename(out_path)} with tracking drift (dy={dy:.1f}, dx={dx:.1f})")
EOF

# Run preparation script
sudo -u ga python3 /tmp/prepare_drifting_frames.py

# Launch AstroImageJ
echo "Launching AstroImageJ..."
if ! pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh &"
    sleep 8
fi

# Wait for AIJ window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ"; then
        break
    fi
    sleep 1
done

# Focus AIJ
DISPLAY=:1 wmctrl -a "AstroImageJ" 2>/dev/null || DISPLAY=:1 wmctrl -a "ImageJ" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="