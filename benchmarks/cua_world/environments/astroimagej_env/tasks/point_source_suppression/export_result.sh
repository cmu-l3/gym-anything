#!/bin/bash
# Export script for Point Source Suppression task
set -euo pipefail

echo "=== Exporting Point Source Suppression Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png ga

WORK_DIR="/home/ga/AstroImages/nebula_analysis"
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Collect result data via Python
python3 << EOF
import json
import os
import glob
import re
import numpy as np
from scipy import ndimage
try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

WORK_DIR = "$WORK_DIR"
START_TIME = $START_TIME

result = {
    "fits_exists": False,
    "txt_exists": False,
    "fits_created_after_start": False,
    "txt_created_after_start": False,
    "txt_content": "",
    "filtered_median": None,
    "filtered_max": None,
    "filtered_sources": None,
    "analysis_error": None
}

fits_path = os.path.join(WORK_DIR, "starless_ha.fits")
txt_path = os.path.join(WORK_DIR, "suppression_stats.txt")

# Check FITS
if os.path.exists(fits_path):
    result["fits_exists"] = True
    if os.path.getmtime(fits_path) > START_TIME:
        result["fits_created_after_start"] = True
        
    if HAS_ASTROPY:
        try:
            data = fits.getdata(fits_path).astype(float)
            if data.ndim > 2:
                data = data[0]
            data = np.nan_to_num(data, nan=np.nanmedian(data))
            
            result["filtered_median"] = float(np.median(data))
            result["filtered_max"] = float(np.max(data))
            
            # Count sources using same logic as ground truth
            std_val = float(np.std(data))
            threshold = result["filtered_median"] + 5 * std_val
            labeled, num_features = ndimage.label(data > threshold)
            result["filtered_sources"] = int(num_features)
            
        except Exception as e:
            result["analysis_error"] = str(e)
    else:
        result["analysis_error"] = "astropy not available"

# Check TXT
if os.path.exists(txt_path):
    result["txt_exists"] = True
    if os.path.getmtime(txt_path) > START_TIME:
        result["txt_created_after_start"] = True
    try:
        with open(txt_path, "r") as f:
            result["txt_content"] = f.read()
    except Exception as e:
        result["txt_content"] = f"Error reading file: {e}"

# Also check for AstroImageJ processes to confirm it was running
import subprocess
try:
    proc = subprocess.run(["pgrep", "-f", "astroimagej\|aij\|AstroImageJ"], capture_output=True, text=True)
    result["aij_running"] = len(proc.stdout.strip()) > 0
except:
    result["aij_running"] = False

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

chmod 644 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="