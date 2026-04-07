#!/bin/bash
echo "=== Exporting Eagle Nebula Ratio Map Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot for visual verification
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Extract analytical data using Python
python3 << 'EOF'
import os, json
import numpy as np

try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

WORK_DIR = "/home/ga/AstroImages/eagle_ratio"
out_fits = os.path.join(WORK_DIR, "sii_ha_ratio.fits")
out_txt = os.path.join(WORK_DIR, "ratio_statistics.txt")
start_time_file = "/tmp/task_start_timestamp"

try:
    with open(start_time_file, "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

res = {
    "fits_exists": os.path.exists(out_fits),
    "txt_exists": os.path.exists(out_txt),
    "txt_content": "",
    "fits_stats": None,
    "fits_shape": None,
    "fits_created_during_task": False
}

if res["fits_exists"]:
    mtime = os.path.getmtime(out_fits)
    res["fits_created_during_task"] = mtime >= task_start
    
    if HAS_ASTROPY:
        try:
            d = fits.getdata(out_fits).astype(float)
            res["fits_shape"] = list(d.shape)
            valid = d[np.isfinite(d)]
            if len(valid) > 0:
                res["fits_stats"] = {
                    "median": float(np.median(valid)),
                    "std": float(np.std(valid)),
                    "min": float(np.min(valid)),
                    "max": float(np.max(valid))
                }
        except Exception as e:
            res["fits_error"] = str(e)

if res["txt_exists"]:
    try:
        with open(out_txt, "r") as f:
            res["txt_content"] = f.read()[:2000]
    except:
        pass

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f)
EOF

cat /tmp/task_result.json
echo "Export complete."