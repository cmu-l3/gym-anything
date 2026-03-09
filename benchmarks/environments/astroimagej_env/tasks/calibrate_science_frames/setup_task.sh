#!/bin/bash
echo "=== Setting up CCD Calibration Pipeline Task ==="

source /workspace/scripts/task_utils.sh

# Create project directories
PROJECT_DIR="/home/ga/AstroImages/calibration_project"
REDUCED_DIR="$PROJECT_DIR/reduced"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"/{bias,dark,flat,science} "$REDUCED_DIR"

# Discover and organize real Palomar LFC data — NO synthetic data generation
python3 << 'PYEOF'
import os, shutil, json, glob
from astropy.io import fits
import numpy as np

LFC_BASE = "/opt/fits_samples/palomar_lfc"
WORK_DIR = "/home/ga/AstroImages/calibration_project"

# Find all FITS files recursively
fits_files = []
for root, dirs, files in os.walk(LFC_BASE):
    for f in files:
        if f.lower().endswith(('.fits', '.fit', '.fts')):
            fits_files.append(os.path.join(root, f))

print(f"Found {len(fits_files)} FITS files in {LFC_BASE}")

# Classify by IMAGETYP header
categories = {'bias': [], 'dark': [], 'flat': [], 'science': []}

for fpath in sorted(fits_files):
    try:
        hdr = fits.getheader(fpath)
        imgtype = hdr.get('IMAGETYP', '').upper().strip()
        if 'BIAS' in imgtype:
            categories['bias'].append(fpath)
        elif 'DARK' in imgtype:
            categories['dark'].append(fpath)
        elif 'FLAT' in imgtype:
            categories['flat'].append(fpath)
        elif any(x in imgtype for x in ['LIGHT', 'SCIENCE', 'OBJECT']):
            categories['science'].append(fpath)
    except Exception as e:
        print(f"  Skipping {fpath}: {e}")

print("Classified frames:")
for cat, files in categories.items():
    print(f"  {cat}: {len(files)} frames")

# Copy to organized directories
for cat, files in categories.items():
    target_dir = os.path.join(WORK_DIR, cat)
    for i, f in enumerate(files):
        dest = os.path.join(target_dir, f"{cat}_{i+1:03d}.fits")
        shutil.copy2(f, dest)
    print(f"  Copied {len(files)} {cat} frames to {target_dir}")

# Compute ground truth from real data
gt = {'total_files': sum(len(v) for v in categories.values())}

# --- Bias ground truth ---
bias_dir = os.path.join(WORK_DIR, 'bias')
bias_files = sorted(glob.glob(os.path.join(bias_dir, '*.fits')))
if bias_files:
    # Use up to first 20 bias frames for master bias computation
    n_use = min(len(bias_files), 20)
    all_bias = np.array([fits.getdata(f).astype(float) for f in bias_files[:n_use]])
    master_bias = np.median(all_bias, axis=0)
    gt['num_bias'] = len(bias_files)
    gt['bias_mean'] = float(np.mean(master_bias))
    gt['bias_std'] = float(np.std(master_bias))
    gt['bias_median'] = float(np.median(master_bias))
    gt['image_shape'] = list(master_bias.shape)
    print(f"  Master bias stats: mean={gt['bias_mean']:.2f}, std={gt['bias_std']:.2f}, median={gt['bias_median']:.2f}")
    print(f"  Image shape: {gt['image_shape']}")

# --- Dark ground truth ---
dark_dir = os.path.join(WORK_DIR, 'dark')
dark_files = sorted(glob.glob(os.path.join(dark_dir, '*.fits')))
if dark_files:
    hdr = fits.getheader(dark_files[0])
    n_use = min(len(dark_files), 20)
    all_dark = np.array([fits.getdata(f).astype(float) for f in dark_files[:n_use]])
    master_dark_raw = np.median(all_dark, axis=0)
    gt['num_dark'] = len(dark_files)
    gt['dark_mean_raw'] = float(np.mean(master_dark_raw))
    gt['dark_exptime'] = float(hdr.get('EXPTIME', hdr.get('EXPOSURE', 0)))
    # Bias-subtracted dark
    if bias_files:
        master_dark_sub = master_dark_raw - master_bias
        gt['dark_mean_bias_subtracted'] = float(np.mean(master_dark_sub))
        print(f"  Master dark stats: raw_mean={gt['dark_mean_raw']:.2f}, bias_sub_mean={gt['dark_mean_bias_subtracted']:.2f}, exptime={gt['dark_exptime']:.1f}s")
    else:
        print(f"  Master dark stats: raw_mean={gt['dark_mean_raw']:.2f}, exptime={gt['dark_exptime']:.1f}s")

# --- Flat ground truth ---
flat_dir = os.path.join(WORK_DIR, 'flat')
flat_files = sorted(glob.glob(os.path.join(flat_dir, '*.fits')))
if flat_files:
    hdr = fits.getheader(flat_files[0])
    n_use = min(len(flat_files), 20)
    all_flat = np.array([fits.getdata(f).astype(float) for f in flat_files[:n_use]])
    master_flat_raw = np.median(all_flat, axis=0)
    gt['num_flat'] = len(flat_files)
    gt['flat_mean_raw'] = float(np.mean(master_flat_raw))
    gt['flat_exptime'] = float(hdr.get('EXPTIME', hdr.get('EXPOSURE', 0)))
    # Bias-subtracted + normalized flat
    if bias_files:
        master_flat_sub = master_flat_raw - master_bias
        flat_median = float(np.median(master_flat_sub))
        master_flat_norm = master_flat_sub / flat_median
        gt['flat_median_for_norm'] = flat_median
        gt['flat_mean_normalized'] = float(np.mean(master_flat_norm))
        gt['flat_min_normalized'] = float(np.min(master_flat_norm))
        gt['flat_max_normalized'] = float(np.max(master_flat_norm))
        print(f"  Master flat stats: raw_mean={gt['flat_mean_raw']:.2f}, norm_mean={gt['flat_mean_normalized']:.4f}, norm_range=[{gt['flat_min_normalized']:.4f}, {gt['flat_max_normalized']:.4f}]")
    else:
        print(f"  Master flat stats: raw_mean={gt['flat_mean_raw']:.2f}")

# --- Science ground truth ---
sci_dir = os.path.join(WORK_DIR, 'science')
sci_files = sorted(glob.glob(os.path.join(sci_dir, '*.fits')))
if sci_files:
    hdr = fits.getheader(sci_files[0])
    data = fits.getdata(sci_files[0]).astype(float)
    gt['num_science'] = len(sci_files)
    gt['science_mean_raw'] = float(np.mean(data))
    gt['science_exptime'] = float(hdr.get('EXPTIME', hdr.get('EXPOSURE', 0)))
    print(f"  Science stats: {len(sci_files)} frames, raw_mean={gt['science_mean_raw']:.2f}, exptime={gt['science_exptime']:.1f}s")

# Save ground truth JSON
with open('/tmp/calibration_ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)
print(f"\nGround truth saved to /tmp/calibration_ground_truth.json")
print(json.dumps(gt, indent=2))
PYEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record initial state
ls "$REDUCED_DIR"/*.fits 2>/dev/null | wc -l > /tmp/initial_reduced_count
date +%s > /tmp/task_start_timestamp

# Launch AstroImageJ
launch_astroimagej 120

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Project directory: $PROJECT_DIR"
echo "Output directory: $REDUCED_DIR"
echo "Frame counts:"
echo "  Bias:    $(ls "$PROJECT_DIR"/bias/*.fits 2>/dev/null | wc -l)"
echo "  Dark:    $(ls "$PROJECT_DIR"/dark/*.fits 2>/dev/null | wc -l)"
echo "  Flat:    $(ls "$PROJECT_DIR"/flat/*.fits 2>/dev/null | wc -l)"
echo "  Science: $(ls "$PROJECT_DIR"/science/*.fits 2>/dev/null | wc -l)"
