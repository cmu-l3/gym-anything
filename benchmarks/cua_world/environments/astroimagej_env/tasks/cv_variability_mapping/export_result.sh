#!/bin/bash
echo "=== Exporting CV Variability Mapping Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

echo "Running Python verification script..."
python3 << 'PYEOF'
import numpy as np
from astropy.io import fits
import glob, os, json, re

stack_dir = "/home/ga/AstroImages/time_series_stack"
output_dir = "/home/ga/AstroImages/cv_output"

files = sorted(glob.glob(os.path.join(stack_dir, "*.fits")))

result = {
    "avg_map_exists": os.path.exists(os.path.join(output_dir, "average_map.fits")),
    "std_map_exists": os.path.exists(os.path.join(output_dir, "std_map.fits")),
    "cv_map_exists": os.path.exists(os.path.join(output_dir, "cv_map.fits")),
    "stats_file_exists": os.path.exists(os.path.join(output_dir, "cv_statistics.txt")),
    "avg_is_correct": False,
    "std_is_correct": False,
    "cv_is_correct": False,
    "cv_math_is_correct": False,
    "reported_mean_cv": None,
    "reported_max_cv": None,
    "actual_mean_cv": None,
    "actual_max_cv": None,
    "error": None
}

if result["stats_file_exists"]:
    try:
        with open(os.path.join(output_dir, "cv_statistics.txt"), "r") as f:
            content = f.read()
            mean_match = re.search(r'mean_cv:\s*([-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)', content, re.IGNORECASE)
            if mean_match: result["reported_mean_cv"] = float(mean_match.group(1))
            max_match = re.search(r'max_cv:\s*([-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)', content, re.IGNORECASE)
            if max_match: result["reported_max_cv"] = float(max_match.group(1))
    except Exception as e:
        result["error"] = f"Stats parsing error: {e}"

if files:
    try:
        data = [fits.getdata(f).astype(np.float64) for f in files]
        data_stack = np.array(data)
        
        gt_avg = np.mean(data_stack, axis=0)
        gt_std = np.std(data_stack, axis=0, ddof=1)
        gt_cv = np.zeros_like(gt_std)
        mask = gt_avg != 0
        gt_cv[mask] = gt_std[mask] / gt_avg[mask]
        
        if result["avg_map_exists"]:
            user_avg = fits.getdata(os.path.join(output_dir, "average_map.fits")).astype(np.float64)
            if user_avg.shape == gt_avg.shape:
                diff = np.abs(user_avg - gt_avg)
                result["avg_diff_mean"] = float(np.nanmean(diff))
                result["avg_is_correct"] = result["avg_diff_mean"] < 1.0
            
        if result["std_map_exists"]:
            user_std = fits.getdata(os.path.join(output_dir, "std_map.fits")).astype(np.float64)
            if user_std.shape == gt_std.shape:
                diff = np.abs(user_std - gt_std)
                result["std_diff_mean"] = float(np.nanmean(diff))
                result["std_is_correct"] = result["std_diff_mean"] < 1.0
            
        if result["cv_map_exists"]:
            user_cv = fits.getdata(os.path.join(output_dir, "cv_map.fits")).astype(np.float64)
            if user_cv.shape == gt_cv.shape:
                diff = np.abs(user_cv - gt_cv)
                result["cv_diff_mean"] = float(np.nanmean(diff))
                result["cv_is_correct"] = result["cv_diff_mean"] < 0.05
                
                user_cv_finite = user_cv[np.isfinite(user_cv)]
                if len(user_cv_finite) > 0:
                    result["actual_mean_cv"] = float(np.mean(user_cv_finite))
                    result["actual_max_cv"] = float(np.max(user_cv_finite))

                if result["avg_map_exists"] and result["std_map_exists"] and user_avg.shape == user_std.shape == user_cv.shape:
                    math_cv = np.zeros_like(user_std)
                    umask = user_avg != 0
                    math_cv[umask] = user_std[umask] / user_avg[umask]
                    diff_math = np.abs(user_cv - math_cv)
                    result["cv_math_diff_mean"] = float(np.nanmean(diff_math))
                    result["cv_math_is_correct"] = result["cv_math_diff_mean"] < 0.05

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="