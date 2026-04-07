#!/bin/bash
echo "=== Exporting CCD Variance Map Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual verification
take_screenshot /tmp/task_end_screenshot.png

# Analyze output files and compute mathematical correctness
python3 << 'PYEOF'
import json
import os
import re
try:
    from astropy.io import fits
    import numpy as np
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

PROJECT = "/home/ga/AstroImages/noise_mapping"
START_TIME = 0
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        START_TIME = int(f.read().strip())
except:
    pass

result = {
    "var_map_exists": False,
    "err_map_exists": False,
    "results_file_exists": False,
    "var_map_created_during_task": False,
    "err_map_created_during_task": False,
    "var_map_accurate": False,
    "err_map_accurate": False,
    "reported_mean_error": None,
    "true_mean_error": None,
    "var_map_error_msg": "",
    "err_map_error_msg": "",
    "astropy_available": HAS_ASTROPY
}

orig_path = os.path.join(PROJECT, "ngc6652_555w.fits")
var_path = os.path.join(PROJECT, "variance_map.fits")
err_path = os.path.join(PROJECT, "error_map.fits")
res_path = os.path.join(PROJECT, "results.txt")

if HAS_ASTROPY and os.path.exists(orig_path):
    try:
        # Load ground truth original
        with fits.open(orig_path) as hdul:
            orig_data = hdul[0].data.astype(np.float64) # Use float64 to avoid precision loss in truth
        
        # Ground Truth Math
        gt_var = (orig_data * 7.12) + (5.24**2)
        gt_err = np.sqrt(np.maximum(0, gt_var))
        result["true_mean_error"] = float(np.nanmean(gt_err))
        
        # Check Variance Map
        if os.path.exists(var_path):
            result["var_map_exists"] = True
            result["var_map_created_during_task"] = os.path.getmtime(var_path) >= START_TIME
            try:
                with fits.open(var_path) as hdul:
                    agent_var = hdul[0].data.astype(np.float64)
                if agent_var.shape == gt_var.shape:
                    # Allow 0.1% tolerance or small absolute tolerance due to 32-bit float saving in ImageJ
                    match = np.allclose(agent_var, gt_var, rtol=1e-3, atol=1.0, equal_nan=True)
                    result["var_map_accurate"] = bool(match)
                    if not match:
                        diff = np.nanmean(np.abs(agent_var - gt_var))
                        result["var_map_error_msg"] = f"Mean absolute difference: {diff:.4f}"
                else:
                    result["var_map_error_msg"] = f"Shape mismatch: expected {gt_var.shape}, got {agent_var.shape}"
            except Exception as e:
                result["var_map_error_msg"] = f"FITS read error: {e}"

        # Check Error Map
        if os.path.exists(err_path):
            result["err_map_exists"] = True
            result["err_map_created_during_task"] = os.path.getmtime(err_path) >= START_TIME
            try:
                with fits.open(err_path) as hdul:
                    agent_err = hdul[0].data.astype(np.float64)
                if agent_err.shape == gt_err.shape:
                    match = np.allclose(agent_err, gt_err, rtol=1e-3, atol=1.0, equal_nan=True)
                    result["err_map_accurate"] = bool(match)
                    if not match:
                        nans_agent = np.isnan(agent_err).sum()
                        nans_gt = np.isnan(gt_err).sum()
                        if nans_agent > nans_gt:
                            result["err_map_error_msg"] = f"Agent map has {nans_agent} NaNs (forgot Max 0?)"
                        else:
                            diff = np.nanmean(np.abs(agent_err - gt_err))
                            result["err_map_error_msg"] = f"Mean absolute difference: {diff:.4f}"
                else:
                    result["err_map_error_msg"] = f"Shape mismatch: expected {gt_err.shape}, got {agent_err.shape}"
            except Exception as e:
                result["err_map_error_msg"] = f"FITS read error: {e}"
    except Exception as e:
        result["var_map_error_msg"] = f"Ground truth calculation error: {e}"
else:
    # Just check existence if astropy failed
    result["var_map_exists"] = os.path.exists(var_path)
    result["err_map_exists"] = os.path.exists(err_path)

# Check Results Text File
if os.path.exists(res_path):
    result["results_file_exists"] = True
    try:
        with open(res_path, 'r') as f:
            content = f.read()
        match = re.search(r'MEAN_ERROR:\s*([0-9.]+)', content, re.IGNORECASE)
        if match:
            result["reported_mean_error"] = float(match.group(1))
    except Exception as e:
        pass

# Ensure AstroImageJ was actually running during export
result["aij_running"] = os.system("pgrep -f 'astroimagej\|aij\|AstroImageJ' > /dev/null") == 0

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="