#!/bin/bash
echo "=== Exporting MOS Target Selection Results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python script inside the container to safely process the FITS, CSV, and ZIP
python3 << EOF
import os
import json
import zipfile
import math
import traceback

try:
    import pandas as pd
    HAS_PANDAS = True
except ImportError:
    HAS_PANDAS = False

try:
    from astropy.io import fits
    import numpy as np
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

PROJECT_DIR = "/home/ga/AstroImages/mos_planning"
CSV_FILE = os.path.join(PROJECT_DIR, "mos_targets.csv")
ZIP_FILE = os.path.join(PROJECT_DIR, "mos_targets.zip")
FITS_FILE = os.path.join(PROJECT_DIR, "ngc6652_555wmos.fits")
START_TIME = int("$START_TIME")

result = {
    "csv_exists": False,
    "zip_exists": False,
    "csv_created_during_task": False,
    "zip_created_during_task": False,
    "num_rows": 0,
    "num_rois_in_zip": 0,
    "areas_correct": False,
    "areas": [],
    "min_distance": 0.0,
    "all_stars_real": False,
    "real_star_count": 0,
    "error": None
}

if os.path.exists(CSV_FILE):
    result["csv_exists"] = True
    if os.path.getmtime(CSV_FILE) >= START_TIME:
        result["csv_created_during_task"] = True

if os.path.exists(ZIP_FILE):
    result["zip_exists"] = True
    if os.path.getmtime(ZIP_FILE) >= START_TIME:
        result["zip_created_during_task"] = True
    try:
        with zipfile.ZipFile(ZIP_FILE, 'r') as z:
            rois = [f for f in z.namelist() if f.endswith('.roi')]
            result["num_rois_in_zip"] = len(rois)
    except Exception:
        pass

# Parse CSV
coords = []
areas = []
if result["csv_exists"]:
    try:
        if HAS_PANDAS:
            # Infer separator to handle AIJ's default tab-separated .xls often saved as .csv
            df = pd.read_csv(CSV_FILE, sep=None, engine='python')
            cols = [str(c).lower().strip() for c in df.columns]
            
            x_col = next((c for c in df.columns if str(c).lower().strip() in ['x', 'xm', 'centroid_x', 'centroid x']), None)
            y_col = next((c for c in df.columns if str(c).lower().strip() in ['y', 'ym', 'centroid_y', 'centroid y']), None)
            area_col = next((c for c in df.columns if str(c).lower().strip() == 'area'), None)
            
            if x_col and y_col:
                for idx, row in df.iterrows():
                    try:
                        coords.append((float(row[x_col]), float(row[y_col])))
                    except ValueError:
                        pass
            
            if area_col:
                for val in df[area_col]:
                    try:
                        areas.append(float(val))
                    except ValueError:
                        pass
                result["areas"] = areas
                if all(70 <= a <= 85 for a in areas) and len(areas) >= 8:
                    result["areas_correct"] = True
                    
            result["num_rows"] = len(df)
        else:
            # Fallback parser
            with open(CSV_FILE, 'r') as f:
                content = f.read().strip()
            sep = '\t' if '\t' in content and ',' not in content else ','
            lines = [line for line in content.split('\n') if line.strip()]
            
            if len(lines) > 1:
                headers = [h.strip().lower() for h in lines[0].split(sep)]
                x_idx, y_idx, area_idx = -1, -1, -1
                for i, h in enumerate(headers):
                    if h in ['x', 'xm', 'centroid_x', 'centroid x']: x_idx = i
                    if h in ['y', 'ym', 'centroid_y', 'centroid y']: y_idx = i
                    if h == 'area': area_idx = i
                
                for line in lines[1:]:
                    parts = [p.strip() for p in line.split(sep)]
                    if len(parts) > max(x_idx, y_idx, area_idx):
                        if x_idx >= 0 and y_idx >= 0:
                            coords.append((float(parts[x_idx]), float(parts[y_idx])))
                        if area_idx >= 0:
                            areas.append(float(parts[area_idx]))
                
                result["num_rows"] = len(coords)
                result["areas"] = areas
                if all(70 <= a <= 85 for a in areas) and len(areas) >= 8:
                    result["areas_correct"] = True

    except Exception as e:
        result["error"] = "CSV parse error: " + str(e)

# Calculate pairwise distances to verify isolation
if len(coords) >= 2:
    min_dist = float('inf')
    for i in range(len(coords)):
        for j in range(i+1, len(coords)):
            d = math.sqrt((coords[i][0] - coords[j][0])**2 + (coords[i][1] - coords[j][1])**2)
            if d < min_dist:
                min_dist = d
    result["min_distance"] = min_dist
elif len(coords) == 1:
    result["min_distance"] = float('inf')

# Verify stars are real peaks in the FITS image
if HAS_ASTROPY and os.path.exists(FITS_FILE) and coords:
    try:
        data = fits.getdata(FITS_FILE).astype(float)
        if data.ndim == 3:
            data = data[0]
        med = np.nanmedian(data)
        
        real_stars = 0
        for x, y in coords:
            ix, iy = int(round(x)), int(round(y))
            # Extract 5x5 bounding box
            if 2 <= ix < data.shape[1]-2 and 2 <= iy < data.shape[0]-2:
                cutout = data[iy-2:iy+3, ix-2:ix+3]
                peak = np.nanmax(cutout)
                if peak > med * 1.5:  # Valid star detection
                    real_stars += 1
                    
        result["real_star_count"] = real_stars
        if real_stars >= 8:
            result["all_stars_real"] = True
    except Exception as e:
        if not result["error"]:
            result["error"] = "FITS check error: " + str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

echo "=== Export Complete ==="