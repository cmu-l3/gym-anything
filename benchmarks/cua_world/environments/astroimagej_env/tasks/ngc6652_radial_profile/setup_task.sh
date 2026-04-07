#!/bin/bash
set -e
echo "=== Setting up NGC 6652 Radial Profile Task ==="

# Create directories
mkdir -p /home/ga/AstroImages/ngc6652_profile
mkdir -p /home/ga/AstroImages/measurements
chown -R ga:ga /home/ga/AstroImages

# Discover FITS, copy to working directory, and calculate real ground truth
python3 << 'PYEOF'
import os, glob, shutil, json
import numpy as np

try:
    from astropy.io import fits
    from scipy import ndimage
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "astropy", "scipy"])
    from astropy.io import fits
    from scipy import ndimage

NGC_DIR = "/opt/fits_samples/ngc6652"
WORK_DIR = "/home/ga/AstroImages/ngc6652_profile"

# Find or unzip FITS
fits_files = glob.glob(os.path.join(NGC_DIR, "**/*.fits"), recursive=True) + glob.glob(os.path.join(NGC_DIR, "**/*.fit"), recursive=True)
if not fits_files:
    import subprocess
    for z in glob.glob(os.path.join(NGC_DIR, "*.zip")):
        subprocess.run(["unzip", "-o", z, "-d", NGC_DIR])
    fits_files = glob.glob(os.path.join(NGC_DIR, "**/*.fits"), recursive=True) + glob.glob(os.path.join(NGC_DIR, "**/*.fit"), recursive=True)

vband = next((f for f in fits_files if '555' in os.path.basename(f).lower()), fits_files[0])
dest = os.path.join(WORK_DIR, "ngc6652_555w.fits")
shutil.copy2(vband, dest)

# Compute Ground Truth dynamically from the image
data = fits.getdata(dest).astype(float)
if data.ndim == 3: data = data[0]
elif data.ndim > 3: data = data.reshape(-1, data.shape[-1])[:data.shape[-2], :]

# Replace NaN/Inf
med = np.nanmedian(data)
data = np.where(np.isfinite(data), data, med)

# Background (median of 4 corners, 100px square)
h, w = data.shape
cs = 100
bg_pixels = np.concatenate([
    data[:cs, :cs].flatten(), data[:cs, -cs:].flatten(),
    data[-cs:, :cs].flatten(), data[-cs:, -cs:].flatten()
])
bg = float(np.nanmedian(bg_pixels))

# Centroid (Gaussian blur, peak, and center of mass around peak)
smoothed = ndimage.gaussian_filter(data, sigma=10)
py, px = np.unravel_index(np.argmax(smoothed), smoothed.shape)
y0, y1 = max(0, py-100), min(h, py+100)
x0, x1 = max(0, px-100), min(w, px+100)
box = data[y0:y1, x0:x1] - bg
box[box < 0] = 0
cy_box, cx_box = ndimage.center_of_mass(box)
cy, cx = cy_box + y0, cx_box + x0

# Peak brightness
peak = float(np.nanmax(smoothed[max(0, py-5):min(h, py+5), max(0, px-5):min(w, px+5)]))

# Half-light radius (measuring out to 300px max)
y, x = np.indices(data.shape)
r = np.sqrt((x - cx)**2 + (y - cy)**2)
mask = r < 300
r_vals = r[mask]
flux_vals = (data[mask] - bg)

# Sort by radius to create cumulative flux profile
sort_idx = np.argsort(r_vals)
r_sorted = r_vals[sort_idx]
flux_sorted = flux_vals[sort_idx]
cumulative_flux = np.cumsum(flux_sorted)
total_flux = cumulative_flux[-1]
half_flux = total_flux / 2.0
idx_half = np.searchsorted(cumulative_flux, half_flux)
hlr = float(r_sorted[idx_half])

gt = {
    "center_x": float(cx),
    "center_y": float(cy),
    "background": bg,
    "peak_brightness": peak,
    "half_light_radius": hlr,
    "total_flux": float(total_flux)
}

# Save ground truth for the verifier (hidden from agent)
with open("/tmp/ngc6652_ground_truth.json", "w") as f:
    json.dump(gt, f)
PYEOF

chown -R ga:ga /home/ga/AstroImages
chmod 644 /tmp/ngc6652_ground_truth.json

# Record anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# Create an AstroImageJ macro to load the image immediately
AIJ_MACRO="/tmp/load_ngc6652.ijm"
cat > "$AIJ_MACRO" << 'MACROEOF'
open("/home/ga/AstroImages/ngc6652_profile/ngc6652_555w.fits");
run("Enhance Contrast", "saturated=0.35");
MACROEOF
chown ga:ga "$AIJ_MACRO"

echo "Starting AstroImageJ..."
su - ga -c "DISPLAY=:1 /usr/local/bin/aij -macro $AIJ_MACRO > /tmp/aij.log 2>&1 &"

# Wait for window to load
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "AstroImageJ\|ImageJ\|ngc6652"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "AstroImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "AstroImageJ" 2>/dev/null || true
sleep 2

DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "=== Task setup complete ==="