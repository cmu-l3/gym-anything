#!/bin/bash
echo "=== Exporting Emission Line Subtraction Result ==="

DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

OUTPUT_FILE="/home/ga/AstroImages/eagle_subtraction/output/halpha_minus_oiii.fits"
REPORT_FILE="/home/ga/AstroImages/eagle_subtraction/output/difference_report.txt"

# Analyze results via python and export JSON
python3 << 'PYEOF'
import os
import json
import re
try:
    from astropy.io import fits
    import numpy as np
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

OUTPUT_FILE = "/home/ga/AstroImages/eagle_subtraction/output/halpha_minus_oiii.fits"
REPORT_FILE = "/home/ga/AstroImages/eagle_subtraction/output/difference_report.txt"

result = {
    "output_fits_exists": os.path.isfile(OUTPUT_FILE),
    "output_report_exists": os.path.isfile(REPORT_FILE),
    "fits_mean": None,
    "fits_std": None,
    "fits_min": None,
    "fits_max": None,
    "fits_shape": None,
    "report_content": "",
    "reported_scale": None,
    "output_created_during_task": False
}

try:
    with open('/tmp/task_start_time', 'r') as f:
        task_start = int(f.read().strip())
    if result["output_fits_exists"]:
        mtime = os.path.getmtime(OUTPUT_FILE)
        if mtime > task_start:
            result["output_created_during_task"] = True
except Exception:
    pass

if HAS_ASTROPY and result["output_fits_exists"]:
    try:
        data = fits.getdata(OUTPUT_FILE).astype(float)
        result["fits_mean"] = float(np.nanmean(data))
        result["fits_std"] = float(np.nanstd(data))
        result["fits_min"] = float(np.nanmin(data))
        result["fits_max"] = float(np.nanmax(data))
        result["fits_shape"] = list(data.shape)
    except Exception as e:
        result["fits_error"] = str(e)

if result["output_report_exists"]:
    try:
        with open(REPORT_FILE, 'r') as f:
            content = f.read()
        result["report_content"] = content[:2000]
        
        # Try to extract scale factor
        scale_match = re.search(r'(?:scale(?: factor)?|ratio|multiplying by)[\s:=]+([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
        if scale_match:
            result["reported_scale"] = float(scale_match.group(1))
    except Exception as e:
        result["report_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON created successfully.")
PYEOF

cat /tmp/task_result.json
echo "=== Export Complete ==="