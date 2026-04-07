#!/bin/bash
echo "=== Exporting Galaxy ROI Task Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/aij_final_screenshot.png ga

# Execute a Python script to robustly parse the agent's output files and FITS dimensions
# We do this in the container to avoid transferring large FITS files, packaging the
# essential numbers into a clean JSON for the verifier on the host.

python3 << 'PYEOF'
import json
import os
import csv
from astropy.io import fits

TASK_START = 0
if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt", "r") as f:
        try:
            TASK_START = int(f.read().strip())
        except:
            pass

res = {
    "csv_exists": False,
    "csv_modified_during_task": False,
    "csv_data": {},
    "roi_exists": False,
    "roi_modified_during_task": False,
    "roi_coords": [],
    "image_shape": None
}

# 1. Get image dimensions to verify centroid
fits_path = "/home/ga/AstroImages/uit_galaxy/uit_galaxy_sample.fits"
try:
    if os.path.exists(fits_path):
        with fits.open(fits_path) as hdul:
            data = hdul[0].data
            if data is not None:
                res["image_shape"] = list(data.shape)
except Exception as e:
    res["fits_error"] = str(e)

# 2. Check and parse CSV file
csv_path = "/home/ga/AstroImages/measurements/galaxy_measurements.csv"
if os.path.exists(csv_path):
    res["csv_exists"] = True
    mtime = int(os.path.getmtime(csv_path))
    res["csv_modified_during_task"] = mtime >= TASK_START
    
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            if rows:
                # Get the last row in case they measured multiple times
                row = rows[-1]
                # Filter to only numeric values and normalize keys
                parsed_row = {}
                for k, v in row.items():
                    if k is None or v is None: continue
                    clean_k = k.strip().lower()
                    clean_v = v.strip()
                    # Basic numeric check
                    if clean_v.replace('.', '', 1).replace('-', '', 1).isdigit():
                        parsed_row[clean_k] = float(clean_v)
                res["csv_data"] = parsed_row
    except Exception as e:
        res["csv_error"] = str(e)

# 3. Check and parse ROI coordinates file
roi_path = "/home/ga/AstroImages/measurements/roi_coordinates.txt"
if os.path.exists(roi_path):
    res["roi_exists"] = True
    mtime = int(os.path.getmtime(roi_path))
    res["roi_modified_during_task"] = mtime >= TASK_START
    
    try:
        coords = []
        with open(roi_path, 'r') as f:
            for line in f:
                parts = line.strip().split()
                # ImageJ XY coordinate files usually have 2 columns (X, Y) or 3 columns (Index, X, Y)
                nums = []
                for p in parts:
                    if p.replace('.', '', 1).replace('-', '', 1).isdigit():
                        nums.append(float(p))
                
                if len(nums) >= 2:
                    # Take the last two numbers as X, Y
                    coords.append([nums[-2], nums[-1]])
        res["roi_coords"] = coords
    except Exception as e:
        res["roi_error"] = str(e)

# 4. Check if AstroImageJ was still running
res["aij_running"] = os.system("pgrep -f 'astroimagej\|aij\|AstroImageJ' > /dev/null") == 0

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f, indent=2)
PYEOF

echo "Task result generated:"
cat /tmp/task_result.json

# Cleanup AIJ to cleanly end
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true

echo "=== Export Complete ==="