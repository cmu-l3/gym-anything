#!/bin/bash
echo "=== Setting up Flat Field Noise Analysis Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/AstroImages/flat_analysis"
FLAT_DIR="$PROJECT_DIR/flats"
RESULTS_DIR="$PROJECT_DIR/results"

# Clean up any old runs
rm -rf "$PROJECT_DIR"
mkdir -p "$FLAT_DIR" "$RESULTS_DIR"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Run Python script to prepare real flat data and calculate ground truth
python3 << 'PYEOF'
import os
import glob
import json
import shutil
import numpy as np
try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

LFC_BASE = "/opt/fits_samples/palomar_lfc"
FLAT_DIR = "/home/ga/AstroImages/flat_analysis/flats"
RESULTS_DIR = "/home/ga/AstroImages/flat_analysis/results"

def generate_fallback_flats():
    print("Generating fallback flats from sample FITS...")
    sample_file = "/opt/fits_samples/hst_wfpc2_sample.fits"
    if not os.path.exists(sample_file):
        # Create a synthetic base if sample is completely missing
        base_data = np.ones((500, 500)) * 1000.0
    else:
        base_data = fits.getdata(sample_file).astype(float)
        # Trim if too large to make processing faster
        if base_data.shape[0] > 1000:
            base_data = base_data[0:1000, 0:1000]
            
    # Simulate a flat with vignetting
    h, w = base_data.shape
    y, x = np.ogrid[-h/2:h/2, -w/2:w/2]
    vignetting = np.exp(-(x**2 + y**2) / (0.8 * (h/2)**2))
    flat_base = base_data * 0.1 + 10000.0 * vignetting
    
    # Generate 10 noisy flats
    for i in range(10):
        # Add poisson noise
        noisy = np.random.poisson(np.clip(flat_base, 1, None)).astype(np.float32)
        # Add a few bad pixels
        noisy[10, 10] = 65000
        noisy[20, 20] = 0
        hdu = fits.PrimaryHDU(noisy)
        hdu.header['IMAGETYP'] = 'FLAT'
        hdu.writeto(f"{FLAT_DIR}/flat_{i+1:02d}.fits", overwrite=True)
    return glob.glob(f"{FLAT_DIR}/*.fits")

# Try to find real Palomar LFC flats
all_fits = glob.glob(f"{LFC_BASE}/**/*.fit*", recursive=True)
flats = []
if HAS_ASTROPY:
    for f in all_fits:
        try:
            hdr = fits.getheader(f)
            if 'FLAT' in hdr.get('IMAGETYP', '').upper():
                flats.append(f)
        except Exception:
            pass

flats = sorted(flats)

# If no real flats found, use fallback
if len(flats) < 3:
    print("Warning: Real flats not found or insufficient. Using fallback.")
    flat_files = generate_fallback_flats()
else:
    # Use up to 10 flats to keep processing time reasonable
    flat_files = flats[:10]
    for i, src in enumerate(flat_files):
        dest = os.path.join(FLAT_DIR, f"flat_{i+1:02d}.fits")
        shutil.copy2(src, dest)
    flat_files = glob.glob(f"{FLAT_DIR}/*.fit*")

print(f"Prepared {len(flat_files)} flat field frames.")

# --- Calculate Ground Truth ---
data_stack = []
for f in sorted(flat_files):
    data_stack.append(fits.getdata(f).astype(float))

stack = np.array(data_stack)

# Master median and stddev
med_proj = np.median(stack, axis=0)
std_proj = np.std(stack, axis=0)

h, w = med_proj.shape

# Quadrant slices
q_slices = [
    (slice(0, h//2), slice(0, w//2)),
    (slice(0, h//2), slice(w//2, w)),
    (slice(h//2, h), slice(0, w//2)),
    (slice(h//2, h), slice(w//2, w))
]

signals = [float(np.median(med_proj[q])) for q in q_slices]
noises = [float(np.median(std_proj[q])) for q in q_slices]
gains = [s / (n**2) if n > 0 else 0 for s, n in zip(signals, noises)]

image_med_std = float(np.median(std_proj))
# Bad pixels: std > 5x median std OR std < 0.1x median std
bad_pixel_mask = (std_proj > 5.0 * image_med_std) | (std_proj < 0.1 * image_med_std)
bad_pixel_count = int(np.sum(bad_pixel_mask))

gt = {
    "num_frames": len(flat_files),
    "shape": [h, w],
    "med_mean": float(np.mean(med_proj)),
    "std_mean": float(np.mean(std_proj)),
    "signals": signals,
    "noises": noises,
    "gains": gains,
    "mean_gain": float(np.mean(gains)),
    "image_med_std": image_med_std,
    "bad_pixel_count": bad_pixel_count
}

print(f"Ground Truth Gain: {gt['mean_gain']:.2f} e-/ADU")
print(f"Ground Truth Bad Pixels: {gt['bad_pixel_count']}")

with open('/tmp/flat_noise_ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)

PYEOF

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Write instructions for the agent into the folder
cat > "$PROJECT_DIR/README.txt" << 'EOF'
FLAT FIELD NOISE ANALYSIS INSTRUCTIONS

1. Open flats/ sequence in AstroImageJ
2. Create Median Z-projection -> save as results/median_flat.fits
3. Create Standard Deviation Z-projection -> save as results/stddev_flat.fits
4. Measure median signal and noise in 4 quadrants
5. Calculate gain = signal / noise^2
6. Count bad pixels in stddev image (outliers >5 sigma)
7. Save results/noise_analysis.txt (see prompt for exact format)
EOF
chown ga:ga "$PROJECT_DIR/README.txt"

# Launch AstroImageJ
echo "Launching AstroImageJ..."
if ! pgrep -f "AstroImageJ\|aij" > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/aij > /tmp/aij.log 2>&1 &"
    sleep 10
fi

# Ensure window is maximized
WID=$(DISPLAY=:1 wmctrl -l | grep -i "AstroImageJ\|ImageJ" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="