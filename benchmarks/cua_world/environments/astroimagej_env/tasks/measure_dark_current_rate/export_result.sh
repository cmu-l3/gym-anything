#!/bin/bash
echo "=== Exporting Measure Dark Current Rate Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract results using Python
python3 << 'PYEOF'
import json
import os
import re

RESULTS_DIR = "/home/ga/AstroImages/dark_current/results"
REPORT_PATH = os.path.join(RESULTS_DIR, "dark_rate_report.txt")
BIAS_PATH = os.path.join(RESULTS_DIR, "master_bias.fits")
DARK_PATH = os.path.join(RESULTS_DIR, "master_dark.fits")

result = {
    "report_exists": False,
    "bias_fits_exists": os.path.isfile(BIAS_PATH),
    "dark_fits_exists": os.path.isfile(DARK_PATH),
    "reported_bias_median": None,
    "reported_dark_median": None,
    "reported_exptime": None,
    "reported_dark_rate": None,
    "report_content": "",
    "bias_fits_mtime": os.path.getmtime(BIAS_PATH) if os.path.isfile(BIAS_PATH) else 0,
    "dark_fits_mtime": os.path.getmtime(DARK_PATH) if os.path.isfile(DARK_PATH) else 0,
    "report_mtime": 0
}

if os.path.isfile(REPORT_PATH):
    result["report_exists"] = True
    result["report_mtime"] = os.path.getmtime(REPORT_PATH)
    
    with open(REPORT_PATH, 'r') as f:
        content = f.read()
        result["report_content"] = content
        
        # Parse fields using regex (case-insensitive, handles spacing)
        bias_match = re.search(r'MASTER_BIAS_MEDIAN:\s*([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
        dark_match = re.search(r'MASTER_DARK_MEDIAN:\s*([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
        time_match = re.search(r'EXPOSURE_TIME:\s*([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
        rate_match = re.search(r'DARK_CURRENT_RATE:\s*([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
        
        if bias_match: result["reported_bias_median"] = float(bias_match.group(1))
        if dark_match: result["reported_dark_median"] = float(dark_match.group(1))
        if time_match: result["reported_exptime"] = float(time_match.group(1))
        if rate_match: result["reported_dark_rate"] = float(rate_match.group(1))

# Read timestamps to prevent gaming
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start_time'] = int(f.read().strip())
    with open('/tmp/task_end_time.txt', 'r') as f:
        result['task_end_time'] = int(f.read().strip())
except Exception:
    result['task_start_time'] = 0
    result['task_end_time'] = 0

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

chmod 777 /tmp/task_result.json
echo "=== Export Complete ==="