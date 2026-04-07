#!/bin/bash
echo "=== Exporting Empirical SNR Map Generation Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE closing anything
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Python script to analyze the math securely and rigorously
python3 << 'PYEOF'
import json
import os
import re
import time
import sys
import numpy as np
from scipy.stats import linregress

try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

WORK_DIR = "/home/ga/AstroImages/snr_analysis"
ORIG_PATH = f"{WORK_DIR}/uit_galaxy_sample.fits"
AGENT_FITS = f"{WORK_DIR}/output/snr_map.fits"
AGENT_TXT = f"{WORK_DIR}/output/snr_results.txt"

# Task start time for anti-gaming checking
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = float(f.read().strip())
except:
    task_start = 0.0

result = {
    "snr_map_exists": False,
    "snr_map_created_during_task": False,
    "snr_results_exists": False,
    "snr_results_created_during_task": False,
    "dtype": "unknown",
    "shape_match": False,
    "r_squared": 0.0,
    "slope": 0.0,
    "intercept": 0.0,
    "extracted_sigma": None,
    "extracted_mu": None,
    "reported_mu": None,
    "reported_sigma": None,
    "reported_area": None,
    "actual_area_gt_3": 0,
    "true_corner_mu": 0.0,
    "true_corner_sigma": 0.0,
    "fits_error": None,
    "txt_error": None
}

if not HAS_ASTROPY:
    result["fits_error"] = "Astropy not installed, cannot verify FITS files programmatically."
else:
    # 1. Measure true background stats (from a roughly blank corner)
    try:
        with fits.open(ORIG_PATH) as hdul:
            orig_data = hdul[0].data.astype(np.float64)
            # Top-left corner usually represents blank sky in this sample
            corner = orig_data[10:100, 10:100]
            result["true_corner_mu"] = float(np.nanmean(corner))
            result["true_corner_sigma"] = float(np.nanstd(corner))
    except Exception as e:
        result["fits_error"] = f"Original FITS read error: {e}"

    # 2. Analyze the agent's output FITS file
    if os.path.exists(AGENT_FITS):
        result["snr_map_exists"] = True
        
        # Check creation time
        mtime = os.path.getmtime(AGENT_FITS)
        if mtime >= task_start:
            result["snr_map_created_during_task"] = True
            
        try:
            with fits.open(AGENT_FITS) as hdul:
                agent_data = hdul[0].data
                result["dtype"] = str(agent_data.dtype)
                agent_data_64 = agent_data.astype(np.float64)
                
                if orig_data.shape == agent_data_64.shape:
                    result["shape_match"] = True
                    
                    # 3. Perform pixel-by-pixel linear regression: Agent = m * Orig + c
                    mask = np.isfinite(orig_data) & np.isfinite(agent_data_64)
                    if np.any(mask):
                        # Use a subset of pixels to speed up if necessary, but 512x512 is small enough
                        o_flat = orig_data[mask]
                        a_flat = agent_data_64[mask]
                        
                        reg = linregress(o_flat, a_flat)
                        result["r_squared"] = float(reg.rvalue**2)
                        result["slope"] = float(reg.slope)
                        result["intercept"] = float(reg.intercept)
                        
                        # Derive the agent's implicitly applied mu and sigma
                        # If S = (O - mu) / sigma = (1/sigma)*O - (mu/sigma)
                        # Then slope = 1/sigma -> sigma = 1/slope
                        # intercept = -mu/sigma -> mu = -intercept / slope
                        if reg.slope > 0:
                            result["extracted_sigma"] = float(1.0 / reg.slope)
                            result["extracted_mu"] = float(-reg.intercept / reg.slope)
                    
                    # 4. Measure the actual area in the agent's map > 3.0
                    result["actual_area_gt_3"] = int(np.sum(agent_data_64 > 3.0))
        except Exception as e:
            result["fits_error"] = f"Agent FITS analysis error: {str(e)}"

# 5. Parse the agent's text results
if os.path.exists(AGENT_TXT):
    result["snr_results_exists"] = True
    
    # Check creation time
    mtime = os.path.getmtime(AGENT_TXT)
    if mtime >= task_start:
        result["snr_results_created_during_task"] = True
        
    try:
        with open(AGENT_TXT, "r") as f:
            content = f.read().lower()
            
        mu_match = re.search(r'background_mean[\s:=]+([0-9]*\.?[0-9]+)', content)
        if mu_match: result["reported_mu"] = float(mu_match.group(1))
        
        sigma_match = re.search(r'background_stddev[\s:=]+([0-9]*\.?[0-9]+)', content)
        if sigma_match: result["reported_sigma"] = float(sigma_match.group(1))
        
        area_match = re.search(r'snr_greater_than_3_area[\s:=]+([0-9]+)', content)
        if area_match: result["reported_area"] = float(area_match.group(1))
        
    except Exception as e:
        result["txt_error"] = f"Txt parsing error: {str(e)}"

# Also record if AIJ was left running
result["aij_running"] = os.system("pgrep -f 'astroimagej\|aij\|AstroImageJ' > /dev/null") == 0

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis Complete. Results:")
print(json.dumps(result, indent=2))
PYEOF

# Clean up AIJ
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true

echo "=== Export Complete ==="