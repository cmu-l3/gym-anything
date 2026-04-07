#!/bin/bash
echo "=== Exporting Star/Galaxy Separation Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE closing application
take_screenshot /tmp/task_end_screenshot.png

# Run Python script to evaluate the results directly against the FITS data
python3 << 'PYEOF'
import json
import os
import re
import glob
from astropy.io import fits
import numpy as np

PROJECT_DIR = "/home/ga/AstroImages/classification"
OUTPUT_DIR = f"{PROJECT_DIR}/output"
FITS_FILE = f"{PROJECT_DIR}/deep_field.fits"

result = {
    "catalog_exists": False,
    "catalog_created_during_task": False,
    "catalog_size_bytes": 0,
    "catalog_lines": 0,
    "report_exists": False,
    "report_created_during_task": False,
    "report_parsed": {},
    "galaxies_verified": [False, False, False],
    "verification_details": []
}

# 1. Check Catalog
# Allow for agent using slightly different extensions (csv, txt, xls, tbl)
catalog_files = glob.glob(f"{OUTPUT_DIR}/source_catalog.*")
if catalog_files:
    cat_file = catalog_files[0]
    result["catalog_exists"] = True
    result["catalog_size_bytes"] = os.path.getsize(cat_file)
    
    # Check if it was created during task
    try:
        with open("/tmp/task_start_timestamp", "r") as f:
            start_time = int(f.read().strip())
        if os.path.getmtime(cat_file) > start_time:
            result["catalog_created_during_task"] = True
    except:
        pass

    # Count lines roughly to ensure they extracted multiple sources
    try:
        with open(cat_file, 'r', encoding='utf-8', errors='ignore') as f:
            result["catalog_lines"] = sum(1 for line in f if line.strip())
    except Exception as e:
        result["verification_details"].append(f"Catalog read error: {str(e)}")

# 2. Check Report
report_file = f"{OUTPUT_DIR}/classification_report.txt"
if os.path.exists(report_file):
    result["report_exists"] = True
    
    # Check creation time
    try:
        with open("/tmp/task_start_timestamp", "r") as f:
            start_time = int(f.read().strip())
        if os.path.getmtime(report_file) > start_time:
            result["report_created_during_task"] = True
    except:
        pass

    # Parse Report
    try:
        with open(report_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        patterns = {
            "CRITERIA_STARS": r"CRITERIA_STARS:\s*(.+)",
            "CRITERIA_GALAXIES": r"CRITERIA_GALAXIES:\s*(.+)",
            "CRITERIA_ARTIFACTS": r"CRITERIA_ARTIFACTS:\s*(.+)",
            "COUNT_STARS": r"COUNT_STARS:\s*(\d+)",
            "COUNT_GALAXIES": r"COUNT_GALAXIES:\s*(\d+)",
            "COUNT_ARTIFACTS": r"COUNT_ARTIFACTS:\s*(\d+)",
            "GALAXY_1_X": r"GALAXY_1_X:\s*([0-9.]+)",
            "GALAXY_1_Y": r"GALAXY_1_Y:\s*([0-9.]+)",
            "GALAXY_2_X": r"GALAXY_2_X:\s*([0-9.]+)",
            "GALAXY_2_Y": r"GALAXY_2_Y:\s*([0-9.]+)",
            "GALAXY_3_X": r"GALAXY_3_X:\s*([0-9.]+)",
            "GALAXY_3_Y": r"GALAXY_3_Y:\s*([0-9.]+)",
        }
        
        parsed = {}
        for key, pattern in patterns.items():
            match = re.search(pattern, content, re.IGNORECASE)
            if match:
                parsed[key] = match.group(1).strip()
        
        result["report_parsed"] = parsed
        
        # 3. Verify Galaxy Coordinates against actual FITS data
        if os.path.exists(FITS_FILE):
            try:
                with fits.open(FITS_FILE) as hdul:
                    data = hdul[0].data
                    if data.ndim == 3:
                        data = data[0]
                        
                    bg_median = np.nanmedian(data)
                    bg_std = np.nanstd(data)
                    
                    for i in range(1, 4):
                        x_str = parsed.get(f"GALAXY_{i}_X")
                        y_str = parsed.get(f"GALAXY_{i}_Y")
                        
                        if x_str and y_str:
                            try:
                                x = int(float(x_str))
                                y = int(float(y_str))
                                
                                # Bounds check (AstroImageJ is 1-indexed, numpy 0-indexed)
                                # Let's handle generic proximity
                                y_idx = max(0, min(data.shape[0]-1, y))
                                x_idx = max(0, min(data.shape[1]-1, x))
                                
                                # Extract 11x11 window around coordinate
                                y_start = max(0, y_idx-5)
                                y_end = min(data.shape[0], y_idx+6)
                                x_start = max(0, x_idx-5)
                                x_end = min(data.shape[1], x_idx+6)
                                
                                window = data[y_start:y_end, x_start:x_end]
                                
                                # A real source should have a peak significantly above background
                                if window.size > 0:
                                    local_max = np.nanmax(window)
                                    # Very loose threshold just to prove it's a real bright object, not blank sky
                                    is_source = local_max > (bg_median + bg_std)
                                    result["galaxies_verified"][i-1] = bool(is_source)
                                    result["verification_details"].append(f"Gal{i} ({x},{y}): max={local_max:.1f}, bg={bg_median:.1f}, is_src={is_source}")
                            except ValueError:
                                result["verification_details"].append(f"Gal{i} coord parse error: {x_str}, {y_str}")
            except Exception as e:
                result["verification_details"].append(f"FITS read error: {str(e)}")

    except Exception as e:
        result["verification_details"].append(f"Report read error: {str(e)}")

# Save the compiled result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="