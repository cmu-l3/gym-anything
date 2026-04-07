#!/bin/bash
set -euo pipefail

echo "=== Exporting Transient Artifacts Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Perform file checks and mathematical comparison using Python
# This avoids transferring huge FITS files out of the environment
python3 << 'PYEOF'
import os, glob, json, re
import numpy as np
try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

result = {
    "has_astropy": HAS_ASTROPY,
    "max_exists": False,
    "median_exists": False,
    "diff_exists": False,
    "report_exists": False,
    "max_mae": None,
    "median_mae": None,
    "diff_mae": None,
    "reported_peak": None,
    "gt_peak": None,
    "files_created_during_task": False,
    "gui_evidence": False
}

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

def check_mtime(filepath):
    return os.path.exists(filepath) and os.path.getmtime(filepath) > task_start

# Evaluate file creation timestamps
artifacts_dir = '/home/ga/AstroImages/artifacts'
max_file = os.path.join(artifacts_dir, 'max_projection.fits')
median_file = os.path.join(artifacts_dir, 'median_projection.fits')
diff_file = os.path.join(artifacts_dir, 'artifact_map.fits')
report_file = os.path.join(artifacts_dir, 'artifact_stats.txt')

created_files = []
for f in [max_file, median_file, diff_file, report_file]:
    if os.path.exists(f):
        created_files.append(check_mtime(f))

result["files_created_during_task"] = all(created_files) if created_files else False

if HAS_ASTROPY:
    # 1. Re-calculate Ground Truth dynamically
    time_series_dir = '/home/ga/AstroImages/time_series'
    images = sorted(glob.glob(os.path.join(time_series_dir, '*.fits')))
    
    if len(images) > 0:
        stack = np.array([fits.getdata(img) for img in images]).astype(float)
        gt_max = np.nanmax(stack, axis=0)
        gt_median = np.nanmedian(stack, axis=0)
        gt_diff = gt_max - gt_median
        
        result["gt_peak"] = float(np.nanmax(gt_diff))
        
        # 2. Compare Agent Files with Ground Truth
        def get_mae(agent_file, gt_array):
            if os.path.exists(agent_file):
                try:
                    agent_data = fits.getdata(agent_file).astype(float)
                    agent_data = np.squeeze(agent_data) # handle extra dims if any
                    if agent_data.shape == gt_array.shape:
                        return float(np.nanmean(np.abs(agent_data - gt_array)))
                except Exception:
                    pass
            return None
            
        result["max_mae"] = get_mae(max_file, gt_max)
        result["median_mae"] = get_mae(median_file, gt_median)
        result["diff_mae"] = get_mae(diff_file, gt_diff)

result["max_exists"] = os.path.exists(max_file)
result["median_exists"] = os.path.exists(median_file)
result["diff_exists"] = os.path.exists(diff_file)
result["report_exists"] = os.path.exists(report_file)

# Parse report
if result["report_exists"]:
    try:
        with open(report_file, 'r') as f:
            content = f.read()
        # Find numeric value
        m = re.search(r'([0-9]+\.?[0-9]*[eE]?[-+]?[0-9]*)', content)
        if m:
            result["reported_peak"] = float(m.group(1))
    except Exception:
        pass

# Check AIJ log for evidence of GUI tool usage instead of Python scripts
log_file = '/tmp/astroimagej_ga.log'
if os.path.exists(log_file):
    with open(log_file, 'r') as f:
        log = f.read()
    if 'ZProject' in log or 'ImageCalculator' in log or 'Image Sequence' in log:
        result["gui_evidence"] = True

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Result JSON saved:"
cat /tmp/task_result.json

echo "=== Export Complete ==="