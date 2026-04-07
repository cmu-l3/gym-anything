#!/bin/bash
echo "=== Exporting Logarithmic Rescaling Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
OUT_FITS="/home/ga/AstroImages/eagle_log/output/eagle_halpha_logscaled.fits"
OUT_REPORT="/home/ga/AstroImages/eagle_log/output/transform_report.txt"

# Analyze the agent's outputs using Python
python3 << PYEOF
import json
import os
import re
import numpy as np
from astropy.io import fits

task_start = int("$TASK_START")
out_fits = "$OUT_FITS"
out_report = "$OUT_REPORT"

result = {
    "fits_exists": False,
    "fits_created_during_task": False,
    "fits_valid": False,
    "agent_fits_mean": None,
    "agent_fits_max": None,
    "report_exists": False,
    "report_created_during_task": False,
    "reported_stats": {},
}

# 1. Analyze Output FITS
if os.path.exists(out_fits):
    result["fits_exists"] = True
    mtime = int(os.path.getmtime(out_fits))
    if mtime >= task_start:
        result["fits_created_during_task"] = True
        
    try:
        with fits.open(out_fits) as hdul:
            for hdu in hdul:
                if hdu.data is not None:
                    data = hdu.data.astype(np.float64)
                    valid_data = data[~np.isnan(data)]
                    result["agent_fits_mean"] = float(np.mean(valid_data))
                    result["agent_fits_max"] = float(np.max(valid_data))
                    result["fits_valid"] = True
                    break
    except Exception as e:
        result["fits_error"] = str(e)

# 2. Analyze Output Report
if os.path.exists(out_report):
    result["report_exists"] = True
    mtime = int(os.path.getmtime(out_report))
    if mtime >= task_start:
        result["report_created_during_task"] = True
        
    try:
        with open(out_report, 'r') as f:
            content = f.read()
            
        # Parse the requested keys
        keys_to_find = [
            "ORIGINAL_MIN", "ORIGINAL_MAX", "ORIGINAL_MEAN", "ORIGINAL_STDDEV",
            "TRANSFORMED_MIN", "TRANSFORMED_MAX", "TRANSFORMED_MEAN", "TRANSFORMED_STDDEV",
            "DYNAMIC_RANGE_ORIGINAL", "DYNAMIC_RANGE_TRANSFORMED", "TRANSFORM_METHOD"
        ]
        
        for key in keys_to_find:
            # Look for KEYWORD: value
            match = re.search(rf"{key}\s*:\s*(.+)$", content, re.IGNORECASE | re.MULTILINE)
            if match:
                val_str = match.group(1).strip()
                if key == "TRANSFORM_METHOD":
                    result["reported_stats"][key] = val_str
                else:
                    try:
                        # Extract the first numerical value found
                        num_match = re.search(r'[-+]?\d*\.\d+|\d+', val_str)
                        if num_match:
                            result["reported_stats"][key] = float(num_match.group())
                    except ValueError:
                        result["reported_stats"][key] = val_str
                        
    except Exception as e:
        result["report_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Ensure permissions on the result file
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

# Close AstroImageJ
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true

echo "=== Export Complete ==="