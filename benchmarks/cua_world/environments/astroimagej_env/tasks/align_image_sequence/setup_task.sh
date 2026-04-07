#!/bin/bash
set -e
echo "=== Setting up align_image_sequence task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

RAW_DIR="/home/ga/AstroImages/raw/drift_series"
PROC_DIR="/home/ga/AstroImages/processed/aligned_series"

# Prepare clean directories
sudo -u ga mkdir -p "$RAW_DIR"
sudo -u ga mkdir -p "$PROC_DIR"
rm -f "$RAW_DIR"/*.fits 2>/dev/null || true
rm -f "$PROC_DIR"/*.fits 2>/dev/null || true

# Generate realistic drifting sequence by applying shifts to a real HST sample
echo "Generating drifted sequence from authentic HST sample..."
cat > /tmp/generate_drift.py << 'EOF'
import os
import numpy as np
from astropy.io import fits
from scipy.ndimage import shift

in_file = "/opt/fits_samples/hst_wfpc2_sample.fits"
out_dir = "/home/ga/AstroImages/raw/drift_series"

try:
    # Load real HST reference image
    hdul = fits.open(in_file)
    data = hdul[0].data
    if data is None and len(hdul) > 1:
        data = hdul[1].data
except Exception:
    print("Warning: HST sample not found, falling back to simulated array")
    data = np.random.poisson(15, (512, 512)).astype(float)
    for x, y in [(256, 256), (100, 150), (400, 300), (350, 450), (120, 380)]:
        data[y-2:y+3, x-2:x+3] += 1000

# Crop to 512x512 to keep processing fast while maintaining complexity
h, w = data.shape
if h > 512 and w > 512:
    data = data[h//2-256:h//2+256, w//2-256:w//2+256]

data = np.nan_to_num(data, nan=0.0).astype(np.float32)

for i in range(10):
    # Inject noticeable diagonal tracking drift (dx=4.5, dy=-2.5 per frame)
    shifted = shift(data, (i * -2.5, i * 4.5), mode='reflect')
    
    # Add varying Poisson-like noise to prevent raw duplicate detection
    noise = np.random.normal(0, 5.0, shifted.shape)
    final_data = shifted + noise
    
    out_path = os.path.join(out_dir, f"frame_{i:02d}.fits")
    fits.writeto(out_path, final_data.astype(np.float32), overwrite=True)

print(f"Generated 10 drifting frames in {out_dir}")
EOF

sudo -u ga python3 /tmp/generate_drift.py

# Ensure AstroImageJ is running
if ! pgrep -f "AstroImageJ\|aij" > /dev/null; then
    echo "Starting AstroImageJ..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh" > /dev/null 2>&1 &
    
    # Wait for window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "AstroImageJ"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus application window
DISPLAY=:1 wmctrl -r "AstroImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "AstroImageJ" 2>/dev/null || true

# Allow UI to stabilize and take initial evidence screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="