#!/bin/bash
echo "=== Exporting simulate_ground_based_observation results ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

OUT_FITS="/home/ga/AstroImages/simulations/output/ground_eagle_halpha.fits"
OUT_REPORT="/home/ga/AstroImages/simulations/output/simulation_report.txt"

# Extract actual results from agent's output using Python
python3 << 'PYEOF'
import json
import os
import re
import numpy as np

try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

fits_path = "/home/ga/AstroImages/simulations/output/ground_eagle_halpha.fits"
report_path = "/home/ga/AstroImages/simulations/output/simulation_report.txt"
start_time = int(open("/tmp/task_start_time.txt").read().strip())

result = {
    "fits_exists": os.path.isfile(fits_path),
    "fits_created_during_task": False,
    "fits_w": 0,
    "fits_h": 0,
    "fits_max": 0.0,
    "report_exists": os.path.isfile(report_path),
    "report_content": "",
    "reported_orig_max": None,
    "reported_sim_max": None,
    "reported_w": None,
    "reported_h": None
}

# Process FITS file
if result["fits_exists"]:
    mtime = os.path.getmtime(fits_path)
    if mtime > start_time:
        result["fits_created_during_task"] = True
        
    if HAS_ASTROPY:
        try:
            with fits.open(fits_path) as hdul:
                data = hdul[0].data.astype(float)
                result["fits_h"], result["fits_w"] = data.shape
                result["fits_max"] = float(np.nanmax(data))
        except Exception as e:
            result["fits_error"] = str(e)

# Process Report file
if result["report_exists"]:
    try:
        with open(report_path, "r") as f:
            content = f.read()
            result["report_content"] = content
            
        # Extract values using regex
        orig_match = re.search(r"Original_Max:\s*([0-9]*\.?[0-9]+)", content, re.IGNORECASE)
        if orig_match: result["reported_orig_max"] = float(orig_match.group(1))
        
        sim_match = re.search(r"Simulated_Max:\s*([0-9]*\.?[0-9]+)", content, re.IGNORECASE)
        if sim_match: result["reported_sim_max"] = float(sim_match.group(1))
        
        w_match = re.search(r"Final_Width:\s*([0-9]+)", content, re.IGNORECASE)
        if w_match: result["reported_w"] = int(w_match.group(1))
        
        h_match = re.search(r"Final_Height:\s*([0-9]+)", content, re.IGNORECASE)
        if h_match: result["reported_h"] = int(h_match.group(1))
            
    except Exception as e:
        result["report_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written:"
cat /tmp/task_result.json

echo "=== Export complete ==="