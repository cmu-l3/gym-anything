#!/bin/bash
# Export script for Flat-Field Correction task
# Analyzes the output image and CSV report to generate a verification JSON

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Flat-Field Correction Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# We use Python to parse the TIFF and CSV robustly inside the environment
python3 << 'PYEOF'
import json
import csv
import os
import sys
import numpy as np
from PIL import Image

# Config
image_path = "/home/ga/ImageJ_Data/results/flatfield_corrected.tif"
report_path = "/home/ga/ImageJ_Data/results/illumination_report.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "image_exists": False,
    "report_exists": False,
    "image_valid": False,
    "image_stats": {},
    "report_valid": False,
    "report_data": {},
    "uniformity_improved": False,
    "timestamp_valid": False,
    "errors": []
}

# 1. Check Timestamps
try:
    with open(task_start_file, 'r') as f:
        start_time = int(f.read().strip())
    
    img_mtime = int(os.path.getmtime(image_path)) if os.path.exists(image_path) else 0
    rpt_mtime = int(os.path.getmtime(report_path)) if os.path.exists(report_path) else 0
    
    if img_mtime > start_time and rpt_mtime > start_time:
        output["timestamp_valid"] = True
except Exception as e:
    output["errors"].append(f"Timestamp check failed: {str(e)}")

# 2. Analyze Image
if os.path.exists(image_path):
    output["image_exists"] = True
    try:
        img = Image.open(image_path)
        arr = np.array(img)
        
        output["image_stats"] = {
            "width": img.width,
            "height": img.height,
            "mean": float(np.mean(arr)),
            "std": float(np.std(arr)),
            "min": float(np.min(arr)),
            "max": float(np.max(arr))
        }
        
        # Validation checks
        # Original blobs is 256x254
        dim_ok = (img.width == 256 and img.height == 254)
        # Shouldn't be empty (all 0) or saturated (all 255)
        content_ok = (output["image_stats"]["mean"] > 1.0 and output["image_stats"]["std"] > 0.0)
        
        if dim_ok and content_ok:
            output["image_valid"] = True
            
    except Exception as e:
        output["errors"].append(f"Image analysis failed: {str(e)}")

# 3. Analyze CSV Report
if os.path.exists(report_path):
    output["report_exists"] = True
    try:
        with open(report_path, 'r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
        output["report_data"]["row_count"] = len(rows)
        
        if len(rows) >= 4:
            # Try to identify columns flexibly
            headers = reader.fieldnames or []
            headers_lower = [h.lower() for h in headers]
            
            # Find column mapping
            col_before = next((h for h in headers if 'before' in h.lower() and 'mean' in h.lower()), None)
            if not col_before: col_before = next((h for h in headers if 'before' in h.lower()), None)
            
            col_after = next((h for h in headers if 'after' in h.lower() and 'mean' in h.lower()), None)
            if not col_after: col_after = next((h for h in headers if 'after' in h.lower()), None)
            
            if col_before and col_after:
                before_vals = []
                after_vals = []
                
                for row in rows:
                    try:
                        b = float(row[col_before])
                        a = float(row[col_after])
                        before_vals.append(b)
                        after_vals.append(a)
                    except ValueError:
                        continue
                
                if len(before_vals) >= 4:
                    before_std = np.std(before_vals)
                    after_std = np.std(after_vals)
                    before_mean = np.mean(before_vals)
                    after_mean = np.mean(after_vals)
                    
                    output["report_data"]["stats"] = {
                        "before_std": float(before_std),
                        "after_std": float(after_std),
                        "before_mean": float(before_mean),
                        "after_mean": float(after_mean)
                    }
                    
                    output["report_valid"] = True
                    
                    # Core Success Logic: Uniformity Improvement
                    # Std dev should decrease significantly (meaning flatter field)
                    # We also check that Before wasn't already flat (std > 0)
                    if before_std > 2.0 and after_std < before_std:
                        output["uniformity_improved"] = True
                    # Partial credit if after is very flat
                    elif after_std < 5.0:
                        output["uniformity_improved"] = True
            else:
                output["errors"].append(f"Could not identify Before/After columns. Found: {headers}")
    except Exception as e:
        output["errors"].append(f"Report analysis failed: {str(e)}")

# Save result
with open("/tmp/flatfield_correction_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(json.dumps(output, indent=2))
PYEOF

echo "=== Export Complete ==="