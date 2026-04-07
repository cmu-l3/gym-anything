#!/bin/bash
set -euo pipefail
echo "=== Exporting Cluster Core Extraction Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM evaluation
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Analyzing output files..."
python3 << PYEOF
import os, json
try:
    from astropy.io import fits
    import numpy as np
except ImportError:
    pass

out_fits = "/home/ga/AstroImages/cluster_extraction/output/m12_core_subframe.fits"
out_report = "/home/ga/AstroImages/cluster_extraction/output/extraction_report.txt"
task_start = int("$TASK_START")

res = {
    "task_start_time": task_start,
    "fits_exists": os.path.exists(out_fits),
    "report_exists": os.path.exists(out_report),
    "fits_mtime": os.path.getmtime(out_fits) if os.path.exists(out_fits) else 0,
    "report_mtime": os.path.getmtime(out_report) if os.path.exists(out_report) else 0,
    "fits_size_bytes": os.path.getsize(out_fits) if os.path.exists(out_fits) else 0,
    "sub_shape": None,
    "sub_mean": None,
    "report_content": ""
}

# Determine if files were created during the task
res["fits_created_during_task"] = res["fits_exists"] and res["fits_mtime"] > task_start
res["report_created_during_task"] = res["report_exists"] and res["report_mtime"] > task_start

if res["fits_exists"]:
    try:
        data = fits.getdata(out_fits).astype(float)
        res["sub_shape"] = list(data.shape)
        # Use nanmean to handle potential edge artifact NaNs
        res["sub_mean"] = float(np.nanmean(data))
    except Exception as e:
        res["fits_error"] = str(e)

if res["report_exists"]:
    try:
        with open(out_report, "r") as f:
            res["report_content"] = f.read()[:5000] # Cap length
    except Exception as e:
        res["report_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f)
PYEOF

echo "Task result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="