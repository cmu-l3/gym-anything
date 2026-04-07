#!/bin/bash
echo "=== Exporting Time-Series Stacking Diagnostics Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Analyze the agent's files with python
python3 << 'PYEOF'
import os, json, re
import numpy as np

RESULTS_DIR = "/home/ga/AstroImages/stack_diagnostics/results"
AVG_FILE = f"{RESULTS_DIR}/average_stack.fits"
MED_FILE = f"{RESULTS_DIR}/median_stack.fits"
RES_FILE = f"{RESULTS_DIR}/diagnostic_residuals.fits"
REPORT_FILE = f"{RESULTS_DIR}/diagnostics_report.txt"

result = {
    "avg_file_exists": os.path.isfile(AVG_FILE),
    "med_file_exists": os.path.isfile(MED_FILE),
    "res_file_exists": os.path.isfile(RES_FILE),
    "report_exists": os.path.isfile(REPORT_FILE),
    "res_actual_min": 0.0,
    "res_actual_max": 0.0,
    "reported_max": None,
    "reported_min": None,
    "report_format_correct": False
}

try:
    from astropy.io import fits
    if result["res_file_exists"]:
        data = fits.getdata(RES_FILE).astype(np.float32)
        result["res_actual_min"] = float(np.nanmin(data))
        result["res_actual_max"] = float(np.nanmax(data))
except Exception as e:
    result["fits_error"] = str(e)

if result["report_exists"]:
    try:
        with open(REPORT_FILE, "r") as f:
            content = f.read()
            
        max_match = re.search(r'MAX_RESIDUAL:\s*([+-]?[0-9]*\.?[0-9]+(?:[eE][+-]?[0-9]+)?)', content)
        min_match = re.search(r'MIN_RESIDUAL:\s*([+-]?[0-9]*\.?[0-9]+(?:[eE][+-]?[0-9]+)?)', content)
        
        if max_match and min_match:
            result["reported_max"] = float(max_match.group(1))
            result["reported_min"] = float(min_match.group(1))
            result["report_format_correct"] = True
        else:
            # Fallback permissive regex
            max_match_alt = re.search(r'MAX.*?:?\s*([+-]?[0-9]+\.?[0-9]*(?:[eE][+-]?[0-9]+)?)', content, re.IGNORECASE)
            min_match_alt = re.search(r'MIN.*?:?\s*([+-]?[0-9]+\.?[0-9]*(?:[eE][+-]?[0-9]+)?)', content, re.IGNORECASE)
            if max_match_alt:
                result["reported_max"] = float(max_match_alt.group(1))
            if min_match_alt:
                result["reported_min"] = float(min_match_alt.group(1))
    except Exception as e:
        result["report_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 644 /tmp/task_result.json

# Close AstroImageJ
close_astroimagej

echo "=== Export Complete ==="