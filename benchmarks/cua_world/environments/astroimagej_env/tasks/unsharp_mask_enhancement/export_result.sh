#!/bin/bash
echo "=== Exporting Unsharp Mask Enhancement Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Extract Data and Compute Ground Truth Using Python
python3 << 'PYEOF'
import json
import os
import re
import sys
import numpy as np
from astropy.io import fits
from scipy.ndimage import gaussian_filter

# Configuration
WORK_DIR = "/home/ga/AstroImages/eagle_enhance"
ORIG_FILE = os.path.join(WORK_DIR, "656nmos.fits")
AGENT_FITS = os.path.join(WORK_DIR, "output", "656nmos_unsharp.fits")
AGENT_TXT = os.path.join(WORK_DIR, "output", "enhancement_results.txt")
START_TIME_FILE = "/tmp/task_start_timestamp"

sigma = 5.0
weight = 0.6

result = {
    "agent_fits_exists": False,
    "agent_txt_exists": False,
    "agent_fits_newer_than_start": False,
    "txt_content_raw": "",
    "gt": {},
    "agent_fits_stats": {},
    "parsed_txt_stats": {}
}

try:
    with open(START_TIME_FILE, "r") as f:
        start_time = int(f.read().strip())
except:
    start_time = 0

# --- A. Compute Ground Truth ---
try:
    orig_data = fits.getdata(ORIG_FILE).astype(float)
    # ImageJ Unsharp Mask Formula: sharpened = (original - weight * blurred) / (1 - weight)
    blurred = gaussian_filter(orig_data, sigma=sigma, mode='nearest')
    gt_data = (orig_data - weight * blurred) / (1.0 - weight)
    
    gt_mean = float(np.mean(gt_data))
    gt_std = float(np.std(gt_data))
    
    # Peak location (in Numpy y,x format) -> Convert to ImageJ x,y format
    peak_idx = np.argmax(gt_data)
    peak_y, peak_x = np.unravel_index(peak_idx, gt_data.shape)
    
    result["gt"] = {
        "mean": gt_mean,
        "std": gt_std,
        "peak_x": int(peak_x),
        "peak_y": int(peak_y),
        "orig_std": float(np.std(orig_data)),
        "expected_ratio": gt_std / float(np.std(orig_data)),
        "shape": list(orig_data.shape)
    }
except Exception as e:
    result["gt_error"] = str(e)

# --- B. Analyze Agent's FITS File ---
if os.path.exists(AGENT_FITS):
    result["agent_fits_exists"] = True
    mtime = os.path.getmtime(AGENT_FITS)
    if mtime > start_time:
        result["agent_fits_newer_than_start"] = True
        
    try:
        agent_data = fits.getdata(AGENT_FITS).astype(float)
        agent_mean = float(np.mean(agent_data))
        agent_std = float(np.std(agent_data))
        peak_idx = np.argmax(agent_data)
        peak_y, peak_x = np.unravel_index(peak_idx, agent_data.shape)
        
        result["agent_fits_stats"] = {
            "mean": agent_mean,
            "std": agent_std,
            "peak_x": int(peak_x),
            "peak_y": int(peak_y),
            "shape": list(agent_data.shape),
            "is_identical_to_orig": bool(np.allclose(agent_data, orig_data))
        }
    except Exception as e:
        result["agent_fits_error"] = str(e)

# --- C. Parse Agent's Text Results ---
if os.path.exists(AGENT_TXT):
    result["agent_txt_exists"] = True
    try:
        with open(AGENT_TXT, "r") as f:
            content = f.read()
            result["txt_content_raw"] = content[:2000] # store preview
            
        # Parse logic
        def extract_number(pattern, text):
            m = re.search(pattern, text, re.IGNORECASE)
            if m:
                try:
                    return float(m.group(1))
                except:
                    pass
            return None
            
        # We look for ratio, standard deviations, and peak coordinates
        result["parsed_txt_stats"] = {
            "ratio": extract_number(r'(?:ratio|enhancement).*?([0-9]+\.[0-9]+)', content),
            "orig_std": extract_number(r'(?:orig|initial).*?(?:std|dev).*?([0-9]+\.[0-9]+)', content),
            "enh_std": extract_number(r'(?:enh|unsharp|final).*?(?:std|dev).*?([0-9]+\.[0-9]+)', content),
            "peak_x": extract_number(r'(?:x|x-coord|x=).*?([0-9]{2,4})', content),
            "peak_y": extract_number(r'(?:y|y-coord|y=).*?([0-9]{2,4})', content)
        }
    except Exception as e:
        result["agent_txt_error"] = str(e)

# Save result JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="