#!/bin/bash
echo "=== Exporting Cosmic Ray Counting Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/AstroImages/cosmic_ray_project"
RESULTS_DIR="$PROJECT_DIR/results"

# Analyze files using Python
python3 << PYEOF
import os
import json
import glob
from astropy.io import fits
import numpy as np

PROJECT_DIR = "$PROJECT_DIR"
RESULTS_DIR = "$RESULTS_DIR"
TASK_START = $TASK_START

result = {
    "diff_image_exists": False,
    "diff_image_created_during_task": False,
    "diff_image_stats": {},
    "report_exists": False,
    "report_created_during_task": False,
    "report_content": ""
}

# 1. Check difference image
diff_files = glob.glob(os.path.join(RESULTS_DIR, "*difference*.fits")) + \
             glob.glob(os.path.join(RESULTS_DIR, "*diff*.fits"))
diff_file = diff_files[0] if diff_files else None

if not diff_file:
    # Check alternate locations just in case
    alt_files = glob.glob(os.path.join(PROJECT_DIR, "*difference*.fits"))
    diff_file = alt_files[0] if alt_files else None

if diff_file and os.path.exists(diff_file):
    result["diff_image_exists"] = True
    mtime = os.path.getmtime(diff_file)
    if mtime >= TASK_START:
        result["diff_image_created_during_task"] = True
    
    try:
        with fits.open(diff_file) as hdul:
            data = hdul[0].data
            if data is not None:
                result["diff_image_stats"] = {
                    "shape": list(data.shape),
                    "mean": float(np.nanmean(data)),
                    "median": float(np.nanmedian(data)),
                    "std": float(np.nanstd(data)),
                    "min": float(np.nanmin(data)),
                    "max": float(np.nanmax(data))
                }
    except Exception as e:
        result["diff_image_error"] = str(e)

# 2. Check report file
report_files = glob.glob(os.path.join(RESULTS_DIR, "*report*.txt")) + \
               glob.glob(os.path.join(RESULTS_DIR, "*cosmic*.txt"))
report_file = report_files[0] if report_files else None

if not report_file:
    alt_reports = glob.glob(os.path.join(PROJECT_DIR, "*report*.txt"))
    report_file = alt_reports[0] if alt_reports else None

if report_file and os.path.exists(report_file):
    result["report_exists"] = True
    mtime = os.path.getmtime(report_file)
    if mtime >= TASK_START:
        result["report_created_during_task"] = True
    
    try:
        with open(report_file, 'r', encoding='utf-8') as f:
            result["report_content"] = f.read()[:5000]  # Read up to 5000 chars
    except Exception as e:
        result["report_error"] = str(e)

# Check if AIJ is still running
result["aij_was_running"] = os.system("pgrep -f 'astroimagej\|aij\|AstroImageJ' > /dev/null") == 0

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export Complete ==="