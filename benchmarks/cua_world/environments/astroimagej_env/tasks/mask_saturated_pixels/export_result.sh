#!/bin/bash
echo "=== Exporting Mask Saturated Pixels Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Calculate metrics inside the container using Python and astropy
# This avoids needing to transfer large FITS files to the host for verification
python3 << 'PYEOF'
import json
import os
import re

# Try to import astropy; handle failure gracefully for the JSON export
try:
    from astropy.io import fits
    import numpy as np
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

RAW_FILE = "/home/ga/AstroImages/quality_control/science_raw.fits"
MASK_FILE = "/home/ga/AstroImages/processed/science_masked.fits"
REPORT_FILE = "/home/ga/AstroImages/processed/mask_report.txt"

# Read task start time
task_start_time = 0
try:
    with open("/tmp/task_start_time", "r") as f:
        task_start_time = int(f.read().strip())
except:
    pass

result = {
    "fits_exported": False,
    "report_created": False,
    "file_created_during_task": False,
    "shape_match": False,
    "total_pixels": 0,
    "saturated_pixels_original": 0,
    "masked_correctly": 0,
    "unaffected_preserved": 0,
    "all_zeros": False,
    "reported_count": None,
    "has_astropy": HAS_ASTROPY
}

# 1. Check if the agent created the report file and parse it
if os.path.exists(REPORT_FILE):
    result["report_created"] = True
    try:
        with open(REPORT_FILE, "r") as f:
            content = f.read()
        # Look for "masked_pixel_count: <number>"
        match = re.search(r"masked_pixel_count:\s*(\d+)", content, re.IGNORECASE)
        if match:
            result["reported_count"] = int(match.group(1))
    except Exception as e:
        print(f"Error reading report: {e}")

# 2. Analyze the modified FITS file against the original
if os.path.exists(MASK_FILE) and os.path.exists(RAW_FILE):
    result["fits_exported"] = True
    
    # Check modification time to prevent gaming
    mtime = os.path.getmtime(MASK_FILE)
    if mtime > task_start_time:
        result["file_created_during_task"] = True

    if HAS_ASTROPY:
        try:
            raw_data = fits.getdata(RAW_FILE).astype(float)
            mask_data = fits.getdata(MASK_FILE).astype(float)
            
            # Handle multi-extension or 3D arrays by flattening to compare logic
            if raw_data.shape == mask_data.shape:
                result["shape_match"] = True
                result["total_pixels"] = int(raw_data.size)
                
                # Identify saturated vs unsaturated
                sat_mask = raw_data >= 55000
                unsat_mask = raw_data < 55000
                
                result["saturated_pixels_original"] = int(np.sum(sat_mask))
                
                # Check saturated pixels (should now be exactly 0)
                if result["saturated_pixels_original"] > 0:
                    result["masked_correctly"] = int(np.sum(mask_data[sat_mask] == 0))
                else:
                    result["masked_correctly"] = 0
                    
                # Check unaffected pixels (should be preserved exactly, use small tolerance for float conversions)
                if np.sum(unsat_mask) > 0:
                    diff = np.abs(mask_data[unsat_mask] - raw_data[unsat_mask])
                    result["unaffected_preserved"] = int(np.sum(diff < 1e-4))
                else:
                    result["unaffected_preserved"] = 0
                    
                # Anti-gaming: Check if the whole image was just set to 0
                result["all_zeros"] = bool(np.all(mask_data == 0))
                
        except Exception as e:
            print(f"Error processing FITS arrays: {e}")

# Write results to JSON
try:
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f, indent=2)
except Exception as e:
    print(f"Error saving JSON: {e}")
PYEOF

echo "Task evaluation metrics calculated."
cat /tmp/task_result.json
echo "=== Export Complete ==="