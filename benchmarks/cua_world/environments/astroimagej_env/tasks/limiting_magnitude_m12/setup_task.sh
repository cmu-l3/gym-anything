#!/bin/bash
echo "=== Setting up Limiting Magnitude Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_timestamp

PROJECT_DIR="/home/ga/AstroImages/limiting_mag"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Ensure the real M12 V-band FITS file is available
FITS_SOURCE="/opt/fits_samples/m12/Vcomb.fits"
if [ ! -f "$FITS_SOURCE" ]; then
    echo "Warning: Vcomb.fits not found at $FITS_SOURCE, attempting to extract from zip..."
    if [ -f "/opt/fits_samples/m12/Vcomb.zip" ]; then
        unzip -p "/opt/fits_samples/m12/Vcomb.zip" > "$FITS_SOURCE" 2>/dev/null
    else
        echo "ERROR: Could not find M12 V-band data!"
        exit 1
    fi
fi

cp "$FITS_SOURCE" "$PROJECT_DIR/m12_Vcomb.fits"

# Use Python to analyze the real FITS image, extract actual stars, and generate a
# physically matched reference catalog and ground truth parameters.
python3 << 'PYEOF'
import os, json, math
import numpy as np
from astropy.io import fits
from scipy import ndimage

fits_path = "/home/ga/AstroImages/limiting_mag/m12_Vcomb.fits"
data = fits.getdata(fits_path).astype(float)

# Handle potential NaN values
med_val = np.nanmedian(data)
data = np.where(np.isnan(data), med_val, data)

bg = np.median(data)
std = np.std(data)
threshold = bg + 5 * std

# Detect stars using gaussian blur and thresholding
smoothed = ndimage.gaussian_filter(data, sigma=2.0)
labeled, num_features = ndimage.label(smoothed > threshold)

# Get centroids (limit to 1000 to save time)
num_to_process = min(num_features, 1000)
centroids = ndimage.center_of_mass(data, labeled, range(1, num_to_process + 1))

stars = []
for cy, cx in centroids:
    if np.isnan(cy) or np.isnan(cx):
        continue
    y, x = int(round(cy)), int(round(cx))
    # Exclude edges
    if y < 15 or y > data.shape[0] - 15 or x < 15 or x > data.shape[1] - 15:
        continue
        
    # Simple aperture photometry (r=5) for GT estimation
    aperture = data[y-5:y+6, x-5:x+6]
    flux = np.sum(aperture) - bg * aperture.size
    
    if flux > 100:
        # Calculate approximate SNR (assuming simple poisson + read noise)
        snr = flux / math.sqrt(flux + aperture.size * bg + aperture.size * 25.0)
        # Assign a realistic synthetic V magnitude based on flux (Zero Point ~ 25.0)
        v_mag = -2.5 * math.log10(flux) + 25.0
        
        stars.append({
            'x': float(cx), 
            'y': float(cy), 
            'flux': float(flux), 
            'snr': float(snr), 
            'v_mag': float(v_mag)
        })

# Sort by brightness (lowest V magnitude first)
stars.sort(key=lambda s: s['v_mag'])

# Select exactly 20 stars spanning the brightness range
selected_stars = []
if len(stars) >= 20:
    indices = np.linspace(0, len(stars) - 1, 20).astype(int)
    selected_stars = [stars[i] for i in indices]
else:
    selected_stars = stars

# Format IDs
for i, s in enumerate(selected_stars):
    s['id'] = f"S{i+1:02d}"

# Estimate the limiting magnitude where S/N = 5 using a linear fit in log space
v_mags = np.array([s['v_mag'] for s in selected_stars])
log_snrs = np.array([math.log10(s['snr']) for s in selected_stars if s['snr'] > 0])

if len(v_mags) > 3 and len(log_snrs) == len(v_mags):
    p = np.polyfit(log_snrs, v_mags, 1)
    limiting_mag = float(np.polyval(p, math.log10(5.0)))
else:
    limiting_mag = 21.0 # fallback

# Save Ground Truth
gt = {
    'limiting_magnitude': limiting_mag,
    'stars': selected_stars,
    'total_stars_detected': len(stars)
}
with open('/tmp/limiting_mag_ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)

# Save Reference Catalog for the Agent
catalog_path = "/home/ga/AstroImages/limiting_mag/reference_stars.txt"
with open(catalog_path, 'w') as f:
    f.write("# Reference stars for limiting magnitude analysis\n")
    f.write("# Columns: star_id  x_pixel  y_pixel  V_mag\n")
    f.write("# Measure aperture photometry on these stars and record S/N\n")
    for s in selected_stars:
        f.write(f"{s['id']}  {s['x']:.1f}  {s['y']:.1f}  {s['v_mag']:.2f}\n")

# Write instructions
instructions_path = "/home/ga/AstroImages/limiting_mag/README_instructions.txt"
with open(instructions_path, 'w') as f:
    f.write("Instructions:\n")
    f.write("1. Open m12_Vcomb.fits in AstroImageJ.\n")
    f.write("2. Measure the SNR for at least 8 stars from reference_stars.txt.\n")
    f.write("3. Save your findings strictly in the format requested by the task description.\n")

PYEOF

chown -R ga:ga "$PROJECT_DIR"

# Launch AstroImageJ (agent must load the image themselves)
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize and Focus
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="