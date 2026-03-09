#!/bin/bash
echo "=== Exporting Batch Intensity Normalization Results ==="

# Record end time and capture final screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

RESULTS_DIR="/home/ga/Fiji_Data/results/normalization"
REPORT_FILE="$RESULTS_DIR/normalization_report.csv"
HIST_FILE="$RESULTS_DIR/histogram_comparison.png"

# Python script to analyze output images and generate verified stats
# This runs INSIDE the container to verify the actual pixels of the result files
cat > /tmp/analyze_results.py << 'PYEOF'
import os
import glob
import json
import csv
import numpy as np
from PIL import Image

results_dir = "/home/ga/Fiji_Data/results/normalization"
task_start = int(os.environ.get("TASK_START", 0))

output_data = {
    "images": {},
    "report_exists": False,
    "report_valid": False,
    "histogram_exists": False,
    "files_created_during_task": True
}

# 1. Analyze Output Images
expected_names = [f"normalized_A0{i}.tif" for i in range(1, 6)]
found_images = 0

for fname in expected_names:
    fpath = os.path.join(results_dir, fname)
    img_data = {
        "exists": False,
        "mean": 0,
        "std": 0,
        "width": 0,
        "height": 0,
        "unique_pixels": 0,
        "valid_timestamp": False
    }
    
    if os.path.exists(fpath):
        img_data["exists"] = True
        
        # Check timestamp
        mtime = os.path.getmtime(fpath)
        if mtime > task_start:
            img_data["valid_timestamp"] = True
        else:
            output_data["files_created_during_task"] = False
            
        try:
            with Image.open(fpath) as img:
                img_data["width"], img_data["height"] = img.size
                arr = np.array(img)
                img_data["mean"] = float(np.mean(arr))
                img_data["std"] = float(np.std(arr))
                img_data["unique_pixels"] = len(np.unique(arr))
                found_images += 1
        except Exception as e:
            img_data["error"] = str(e)
            
    output_data["images"][fname] = img_data

output_data["found_images_count"] = found_images

# 2. Verify CSV Report
report_path = os.path.join(results_dir, "normalization_report.csv")
if os.path.exists(report_path):
    output_data["report_exists"] = True
    try:
        with open(report_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            if len(rows) >= 5 and "original_mean" in reader.fieldnames and "normalized_mean" in reader.fieldnames:
                output_data["report_valid"] = True
                output_data["report_rows"] = len(rows)
                # Sample first row data
                output_data["sample_report_data"] = rows[0]
    except Exception as e:
        output_data["report_error"] = str(e)

# 3. Verify Histogram Image
hist_path = os.path.join(results_dir, "histogram_comparison.png")
if os.path.exists(hist_path):
    if os.path.getsize(hist_path) > 5000: # > 5KB
        output_data["histogram_exists"] = True

print(json.dumps(output_data))
PYEOF

# Run analysis and save to result json
export TASK_START
python3 /tmp/analyze_results.py > /tmp/task_result.json

# Cleanup
rm /tmp/analyze_results.py

echo "Result export complete. JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json