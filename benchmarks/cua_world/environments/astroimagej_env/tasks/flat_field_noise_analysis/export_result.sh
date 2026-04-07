#!/bin/bash
echo "=== Exporting Flat Field Noise Analysis Results ==="

# Record task end time and start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application is running
APP_RUNNING=$(pgrep -f "AstroImageJ\|aij" > /dev/null && echo "true" || echo "false")

# Use Python to analyze agent's output files and export to JSON
python3 << 'PYEOF'
import os
import json
import re
import sys
try:
    from astropy.io import fits
    import numpy as np
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

RESULTS_DIR = "/home/ga/AstroImages/flat_analysis/results"
MEDIAN_FILE = os.path.join(RESULTS_DIR, "median_flat.fits")
STDDEV_FILE = os.path.join(RESULTS_DIR, "stddev_flat.fits")
TEXT_FILE = os.path.join(RESULTS_DIR, "noise_analysis.txt")

result = {
    "median_file_exists": os.path.exists(MEDIAN_FILE),
    "stddev_file_exists": os.path.exists(STDDEV_FILE),
    "text_file_exists": os.path.exists(TEXT_FILE),
    "median_stats": None,
    "stddev_stats": None,
    "parsed_text": {
        "signals": [],
        "noises": [],
        "gain": None,
        "bad_pixels": None,
        "poisson_check": None
    },
    "text_content_raw": ""
}

# 1. Analyze FITS files if they exist
if HAS_ASTROPY:
    for filepath, key in [(MEDIAN_FILE, "median_stats"), (STDDEV_FILE, "stddev_stats")]:
        if os.path.exists(filepath):
            try:
                # Check creation time against task start
                mtime = os.path.getmtime(filepath)
                task_start = float(open("/tmp/task_start_time.txt").read().strip() or "0")
                created_during_task = mtime > task_start
                
                with fits.open(filepath) as hdul:
                    data = hdul[0].data
                    if data is not None:
                        result[key] = {
                            "shape": list(data.shape),
                            "mean": float(np.nanmean(data)),
                            "std": float(np.nanstd(data)),
                            "created_during_task": created_during_task
                        }
            except Exception as e:
                result[key] = {"error": str(e)}

# 2. Parse Text file
if os.path.exists(TEXT_FILE):
    try:
        with open(TEXT_FILE, 'r') as f:
            content = f.read()
            result["text_content_raw"] = content[:2000]  # Cap length just in case
            
            lines = [l.strip() for l in content.split('\n') if l.strip()]
            
            if len(lines) > 0:
                result["parsed_text"]["signals"] = [float(x) for x in re.findall(r'[-+]?\d*\.\d+|\d+', lines[0])]
            if len(lines) > 1:
                result["parsed_text"]["noises"] = [float(x) for x in re.findall(r'[-+]?\d*\.\d+|\d+', lines[1])]
            
            # Robust extraction with regex for keys
            gain_match = re.search(r'GAIN_ESTIMATE:\s*([-+]?\d*\.\d+|\d+)', content, re.IGNORECASE)
            if gain_match:
                result["parsed_text"]["gain"] = float(gain_match.group(1))
                
            bad_match = re.search(r'BAD_PIXEL_COUNT:\s*(\d+)', content, re.IGNORECASE)
            if bad_match:
                result["parsed_text"]["bad_pixels"] = int(bad_match.group(1))
                
            poisson_match = re.search(r'POISSON_CHECK:\s*(PASS|FAIL)', content, re.IGNORECASE)
            if poisson_match:
                result["parsed_text"]["poisson_check"] = poisson_match.group(1).upper()
                
    except Exception as e:
        result["text_parse_error"] = str(e)

# Write out the result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export completed successfully.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json