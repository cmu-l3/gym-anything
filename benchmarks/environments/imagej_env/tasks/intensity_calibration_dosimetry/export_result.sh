#!/bin/bash
# Export script for Dosimetry Calibration task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Dosimetry Calibration Results ==="

# Capture final state screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Define paths
RESULT_IMG="/home/ga/ImageJ_Data/results/calibrated_dose_map.tif"
RESULT_CSV="/home/ga/ImageJ_Data/results/dose_report.csv"
JSON_OUT="/tmp/dosimetry_result.json"

# Use Python to analyze the output files (if they exist)
# We perform the analysis inside the container to package the results into a single JSON
python3 << 'PYEOF'
import json
import os
import csv
import numpy as np
from PIL import Image

output = {
    "image_exists": False,
    "csv_exists": False,
    "image_stats": {},
    "csv_stats": {},
    "timestamps_valid": False,
    "task_start": 0,
    "errors": []
}

result_img_path = "/home/ga/ImageJ_Data/results/calibrated_dose_map.tif"
result_csv_path = "/home/ga/ImageJ_Data/results/dose_report.csv"
task_start_path = "/tmp/task_start_timestamp"

try:
    # 1. Check Task Start Time
    if os.path.exists(task_start_path):
        with open(task_start_path, 'r') as f:
            output["task_start"] = int(f.read().strip())

    # 2. Analyze CSV Report
    if os.path.exists(result_csv_path):
        mtime = os.path.getmtime(result_csv_path)
        if mtime > output["task_start"]:
            output["csv_exists"] = True
            
            # Parse CSV content
            try:
                with open(result_csv_path, 'r') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    
                    if rows:
                        # Extract numerical values from likely columns
                        max_vals = []
                        mean_vals = []
                        
                        for row in rows:
                            # Search for 'Max' and 'Mean' columns case-insensitively
                            for k, v in row.items():
                                k_lower = k.lower() if k else ""
                                try:
                                    val = float(v)
                                    if 'max' in k_lower:
                                        max_vals.append(val)
                                    if 'mean' in k_lower:
                                        mean_vals.append(val)
                                except:
                                    pass
                        
                        if max_vals:
                            output["csv_stats"]["max_value"] = max(max_vals)
                        if mean_vals:
                            output["csv_stats"]["mean_value"] = sum(mean_vals) / len(mean_vals)
                        output["csv_stats"]["row_count"] = len(rows)
            except Exception as e:
                output["errors"].append(f"CSV parse error: {str(e)}")

    # 3. Analyze Image
    if os.path.exists(result_img_path):
        mtime = os.path.getmtime(result_img_path)
        # Allow 2 second buffer for timestamp checks
        if mtime > (output["task_start"] - 2):
            output["image_exists"] = True
            
            try:
                # Open image with PIL
                img = Image.open(result_img_path)
                arr = np.array(img)
                
                # Calculate simple stats
                output["image_stats"]["min"] = float(np.min(arr))
                output["image_stats"]["max"] = float(np.max(arr))
                output["image_stats"]["mean"] = float(np.mean(arr))
                output["image_stats"]["dtype"] = str(arr.dtype)
                
            except Exception as e:
                output["errors"].append(f"Image analysis error: {str(e)}")
        else:
            output["errors"].append("Image file is older than task start time")

    # 4. Overall Timestamp Validation
    if output["csv_exists"] or output["image_exists"]:
        output["timestamps_valid"] = True

except Exception as e:
    output["errors"].append(f"General export error: {str(e)}")

# Write result to JSON
with open("/tmp/dosimetry_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Export logic completed.")
PYEOF

echo "JSON output generated at $JSON_OUT"
cat "$JSON_OUT" 2>/dev/null || echo "{}"
echo "=== Export Complete ==="