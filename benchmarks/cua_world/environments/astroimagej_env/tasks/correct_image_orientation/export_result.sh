#!/bin/bash
set -euo pipefail

echo "=== Exporting Image Orientation Task Results ==="

# Record end time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing apps
export DISPLAY=:1
scrot /tmp/task_final.png 2>/dev/null || import -window root /tmp/task_final.png 2>/dev/null || true

# Expected paths
WORK_DIR="/home/ga/AstroImages/orientation"
ORIGINAL_FITS="$WORK_DIR/ngc6652_555w.fits"
EXPECTED_OUTPUT_FITS="$WORK_DIR/corrected/ngc6652_555w_northup.fits"
EXPECTED_REPORT="$WORK_DIR/corrected/orientation_report.txt"

# Analyze the results using Python
python3 << 'PYEOF'
import json
import os
import glob
import time

try:
    from astropy.io import fits
    import numpy as np
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

WORK_DIR = "/home/ga/AstroImages/orientation"
ORIGINAL_FITS = os.path.join(WORK_DIR, "ngc6652_555w.fits")
CORRECTED_DIR = os.path.join(WORK_DIR, "corrected")
EXPECTED_OUTPUT_FITS = os.path.join(CORRECTED_DIR, "ngc6652_555w_northup.fits")
EXPECTED_REPORT = os.path.join(CORRECTED_DIR, "orientation_report.txt")

result = {
    "output_fits_exists": False,
    "output_fits_modified_from_original": False,
    "output_fits_shape": None,
    "original_fits_shape": None,
    "image_modification_score": 0.0,
    "report_exists": False,
    "report_content": "",
    "task_start": int(open('/tmp/task_start_time').read().strip()) if os.path.exists('/tmp/task_start_time') else 0,
    "task_end": int(time.time())
}

# Check if agent saved FITS in alternative locations
actual_output_fits = EXPECTED_OUTPUT_FITS
if not os.path.exists(actual_output_fits):
    # Try finding any new FITS in the corrected dir or working dir
    alt_fits = glob.glob(os.path.join(CORRECTED_DIR, "*.fits")) + \
               glob.glob(os.path.join(WORK_DIR, "*northup*.fits"))
    if alt_fits:
        actual_output_fits = alt_fits[0]

if os.path.exists(actual_output_fits) and actual_output_fits != ORIGINAL_FITS:
    result["output_fits_exists"] = True
    
    if HAS_ASTROPY:
        try:
            # Read original and output to compare
            with fits.open(ORIGINAL_FITS) as hdul_orig:
                orig_data = hdul_orig[0].data.astype(float)
                result["original_fits_shape"] = list(orig_data.shape)
                
            with fits.open(actual_output_fits) as hdul_out:
                out_data = hdul_out[0].data.astype(float)
                result["output_fits_shape"] = list(out_data.shape)
                
            # If shapes are different, it was definitely rotated or cropped
            if orig_data.shape != out_data.shape:
                result["output_fits_modified_from_original"] = True
                result["image_modification_score"] = 1.0
            else:
                # Same shape: check if pixels changed significantly
                # Compare the center 100x100 pixels
                h, w = orig_data.shape
                cy, cx = h//2, w//2
                orig_center = orig_data[cy-50:cy+50, cx-50:cx+50]
                out_center = out_data[cy-50:cy+50, cx-50:cx+50]
                
                # Replace NaNs for safe comparison
                orig_center = np.nan_to_num(orig_center)
                out_center = np.nan_to_num(out_center)
                
                diff = np.mean(np.abs(orig_center - out_center))
                # Normalize difference by original mean
                orig_mean = np.mean(np.abs(orig_center))
                rel_diff = diff / max(orig_mean, 1e-5)
                
                result["image_modification_score"] = float(rel_diff)
                if rel_diff > 0.1: # 10% average pixel difference in center
                    result["output_fits_modified_from_original"] = True
                    
        except Exception as e:
            result["fits_comparison_error"] = str(e)

# Check report
actual_report = EXPECTED_REPORT
if not os.path.exists(actual_report):
    alt_reports = glob.glob(os.path.join(CORRECTED_DIR, "*.txt")) + \
                  glob.glob(os.path.join(WORK_DIR, "*report*.txt"))
    if alt_reports:
        actual_report = alt_reports[0]

if os.path.exists(actual_report):
    result["report_exists"] = True
    try:
        with open(actual_report, 'r', errors='replace') as f:
            result["report_content"] = f.read()[:5000] # Limit size
    except Exception as e:
        result["report_content"] = f"[Error reading report: {e}]"

# Write results
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export completed. FITS exists: {result['output_fits_exists']}, Report exists: {result['report_exists']}")
PYEOF

echo "=== Export Complete ==="