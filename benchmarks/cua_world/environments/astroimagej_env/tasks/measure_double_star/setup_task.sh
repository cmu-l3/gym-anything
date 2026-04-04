#!/bin/bash
echo "=== Setting up Double Star Measurement Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AstroImages/double_star"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Copy real HST NGC 6652 V-band FITS — NO synthetic data generation
NGC6652_DIR="/opt/fits_samples/ngc6652"

# Find and prepare the V-band FITS file, detect a real close star pair
python3 << 'PYEOF'
import os, shutil, glob, json, math, subprocess
from astropy.io import fits
import numpy as np
from scipy import ndimage

NGC_DIR = "/opt/fits_samples/ngc6652"
WORK_DIR = "/home/ga/AstroImages/double_star"
PLATE_SCALE = 0.1  # arcsec/pixel for WFPC2 WF chips

# Find the FITS file — unzip if needed
fits_files = glob.glob(os.path.join(NGC_DIR, "**/*.fits"), recursive=True) + \
             glob.glob(os.path.join(NGC_DIR, "**/*.fit"), recursive=True)

if not fits_files:
    print("No FITS files found, attempting to unzip archives...")
    zips = glob.glob(os.path.join(NGC_DIR, "*.zip"))
    for z in zips:
        subprocess.run(["unzip", "-o", z, "-d", NGC_DIR], check=False)
    fits_files = glob.glob(os.path.join(NGC_DIR, "**/*.fits"), recursive=True) + \
                 glob.glob(os.path.join(NGC_DIR, "**/*.fit"), recursive=True)

if not fits_files:
    raise RuntimeError(f"ERROR: No FITS files found in {NGC_DIR}")

# Pick the V-band (555nm) file
vband = None
for f in fits_files:
    if '555' in os.path.basename(f).lower():
        vband = f
        break
if not vband:
    vband = fits_files[0]

print(f"Using FITS file: {vband}")

# Copy to working directory
dest = os.path.join(WORK_DIR, "ngc6652_555w.fits")
shutil.copy2(vband, dest)

# Add plate scale info to FITS header comments so agent can find it
with fits.open(dest, mode='update') as hdul:
    hdr = hdul[0].header
    hdr['PLATESCL'] = (PLATE_SCALE, 'Plate scale [arcsec/pixel] WFPC2 WF')
    hdr['COMMENT'] = f'WFPC2 Wide Field chip plate scale: {PLATE_SCALE} arcsec/pixel'
    hdr['COMMENT'] = 'Use plate scale to convert pixel separations to arcseconds'
    hdul.flush()

# Read image data and find a close star pair
data = fits.getdata(dest).astype(float)
print(f"Image shape: {data.shape}")

# Handle multi-extension or 3D arrays: take the first 2D plane
if data.ndim == 3:
    data = data[0]
elif data.ndim > 3:
    data = data.reshape(-1, data.shape[-1])[:data.shape[-2], :]

# Replace NaN/Inf with median
med = np.nanmedian(data)
data = np.where(np.isfinite(data), data, med)

# ---- Star detection: find local maxima above threshold ----
smoothed = ndimage.gaussian_filter(data, sigma=2.0)

# Use a high threshold to pick up only bright sources
threshold = np.percentile(smoothed, 99.5)
binary = smoothed > threshold
labeled, num_features = ndimage.label(binary)
print(f"Detected {num_features} source regions above 99.5th percentile")

# If too few, lower threshold
if num_features < 20:
    threshold = np.percentile(smoothed, 99.0)
    binary = smoothed > threshold
    labeled, num_features = ndimage.label(binary)
    print(f"Lowered threshold: {num_features} source regions above 99.0th percentile")

# Get centroids of detected sources (limit to 500 to avoid slowness)
max_sources = min(num_features + 1, 500)
centroids = ndimage.center_of_mass(data, labeled, range(1, max_sources))
print(f"Computing properties for {len(centroids)} sources")

# Measure peak flux and aperture flux at each centroid
border = 15  # pixels from edge to exclude
stars = []
bg_estimate = np.median(data[:50, :50])  # background from corner

for cy, cx in centroids:
    iy, ix = int(round(cy)), int(round(cx))
    if border < iy < data.shape[0] - border and border < ix < data.shape[1] - border:
        peak = float(data[iy - 2:iy + 3, ix - 2:ix + 3].max())
        aperture = data[iy - 5:iy + 6, ix - 5:ix + 6]
        flux = float(np.sum(aperture) - bg_estimate * aperture.size)
        if flux > 0 and peak > threshold * 0.5:
            stars.append({'x': float(cx), 'y': float(cy), 'peak': peak, 'flux': flux})

# Sort by flux (brightest first) and take top 50
stars.sort(key=lambda s: s['flux'], reverse=True)
bright_stars = stars[:50]
print(f"Selected {len(bright_stars)} brightest stars for pair search")

# ---- Find close pairs among bright stars ----
# Target: separation 15-40 pixels (1.5-4.0 arcsec at 0.1"/pix)
# with moderate magnitude difference (interesting for measurement)
best_pair = None
best_score = float('inf')

for i, s1 in enumerate(bright_stars):
    for j, s2 in enumerate(bright_stars):
        if j <= i:
            continue
        dx = s2['x'] - s1['x']
        dy = s2['y'] - s1['y']
        sep = math.sqrt(dx**2 + dy**2)
        if 15 <= sep <= 40:
            # Prefer pairs with moderate flux ratio (1.2x to 5x)
            flux_ratio = max(s1['flux'], s2['flux']) / min(s1['flux'], s2['flux'])
            if 1.2 < flux_ratio < 5.0:
                # Score: prefer closer pairs with moderate contrast
                score = sep + abs(flux_ratio - 2.0) * 10
                if score < best_score:
                    best_score = score
                    if s1['flux'] >= s2['flux']:
                        best_pair = (s1, s2)
                    else:
                        best_pair = (s2, s1)

# Fallback: accept any close pair from top 20
if best_pair is None:
    print("No ideal pair found, using fallback search...")
    for i, s1 in enumerate(bright_stars[:20]):
        for j, s2 in enumerate(bright_stars[:20]):
            if j <= i:
                continue
            dx = s2['x'] - s1['x']
            dy = s2['y'] - s1['y']
            sep = math.sqrt(dx**2 + dy**2)
            if 10 < sep < 60:
                if s1['flux'] >= s2['flux']:
                    best_pair = (s1, s2)
                else:
                    best_pair = (s2, s1)
                break
        if best_pair:
            break

if best_pair is None:
    # Last resort: just pick the two brightest stars
    print("WARNING: Could not find close pair, using two brightest stars")
    best_pair = (bright_stars[0], bright_stars[1])

primary, secondary = best_pair

# ---- Compute ground truth measurements ----
dx = secondary['x'] - primary['x']
# Image Y is inverted relative to celestial N (higher Y = more south in standard orientation)
dy = -(secondary['y'] - primary['y'])
sep_pix = math.sqrt(dx**2 + dy**2)
sep_arcsec = sep_pix * PLATE_SCALE

# Position angle: North through East = atan2(east, north)
pa_deg = math.degrees(math.atan2(dx, dy)) % 360

# Magnitude difference from aperture flux ratio
if secondary['flux'] > 0 and primary['flux'] > 0:
    mag_diff = -2.5 * math.log10(secondary['flux'] / primary['flux'])
else:
    mag_diff = 0.0

print(f"\nTarget pair identified:")
print(f"  Primary:   pixel ({primary['x']:.1f}, {primary['y']:.1f}), flux={primary['flux']:.0f}")
print(f"  Secondary: pixel ({secondary['x']:.1f}, {secondary['y']:.1f}), flux={secondary['flux']:.0f}")
print(f"  Separation: {sep_pix:.1f} pix = {sep_arcsec:.2f} arcsec")
print(f"  Position Angle: {pa_deg:.1f} deg (N through E)")
print(f"  Magnitude difference: {mag_diff:.2f} mag")

# ---- Save target pair info for the agent ----
with open(os.path.join(WORK_DIR, "target_pair.txt"), 'w') as f:
    f.write("Target Double Star Pair in NGC 6652 (HST WFPC2 F555W)\n")
    f.write("=" * 55 + "\n\n")
    f.write(f"Primary star:   approximate pixel ({primary['x']:.0f}, {primary['y']:.0f})\n")
    f.write(f"Secondary star: approximate pixel ({secondary['x']:.0f}, {secondary['y']:.0f})\n\n")
    f.write(f"WFPC2 WF plate scale: {PLATE_SCALE} arcsec/pixel\n")
    f.write(f"(Also recorded in FITS header as PLATESCL keyword)\n\n")
    f.write("Measurements required:\n")
    f.write("  1. Angular separation (arcseconds)\n")
    f.write("  2. Position angle of secondary relative to primary (degrees, N through E)\n")
    f.write("  3. Magnitude difference between the two components\n\n")
    f.write("Save results to: double_star_results.txt\n")

# ---- Save ground truth for verifier (NOT visible to agent) ----
gt = {
    'plate_scale': PLATE_SCALE,
    'primary_x': primary['x'],
    'primary_y': primary['y'],
    'primary_flux': primary['flux'],
    'secondary_x': secondary['x'],
    'secondary_y': secondary['y'],
    'secondary_flux': secondary['flux'],
    'separation_pixels': sep_pix,
    'separation_arcsec': sep_arcsec,
    'position_angle_deg': pa_deg,
    'magnitude_difference': mag_diff,
}
with open('/tmp/double_star_ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)
print(f"\nGround truth saved to /tmp/double_star_ground_truth.json")
PYEOF

chown -R ga:ga "$PROJECT_DIR"

echo "0" > /tmp/initial_results_count
date +%s > /tmp/task_start_timestamp

launch_astroimagej 120
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
