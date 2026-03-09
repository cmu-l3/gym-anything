#!/bin/bash
# Export script for segmentation_validation_ground_truth

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Validation Results ==="

# Paths
RESULTS_DIR="/home/ga/ImageJ_Data/results"
DIFF_IMAGE="$RESULTS_DIR/segmentation_difference.tif"
METRICS_FILE="$RESULTS_DIR/validation_metrics.csv"
TASK_START_FILE="/tmp/task_start_timestamp"

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# Check if application was running
APP_RUNNING="false"
if pgrep -f "fiji\|ImageJ" > /dev/null; then
    APP_RUNNING="true"
fi

# Python script to analyze the output image and CSV
python3 << PYEOF
import json
import os
import csv
import sys
import numpy as np
from PIL import Image

output = {
    "diff_image_exists": False,
    "metrics_file_exists": False,
    "file_created_during_task": False,
    "diff_mean_intensity": -1.0,
    "diff_is_binary": False,
    "metrics_row_count": 0,
    "metrics_has_mean": False,
    "metrics_mean_value": -1.0,
    "app_was_running": str("$APP_RUNNING").lower() == "true",
    "timestamp_check": False
}

task_start = 0
try:
    with open("$TASK_START_FILE", 'r') as f:
        task_start = int(f.read().strip())
except:
    pass

# Analyze Difference Image
if os.path.exists("$DIFF_IMAGE"):
    output["diff_image_exists"] = True
    mtime = os.path.getmtime("$DIFF_IMAGE")
    if mtime > task_start:
        output["file_created_during_task"] = True
        output["timestamp_check"] = True
    
    try:
        img = Image.open("$DIFF_IMAGE")
        arr = np.array(img)
        
        # Calculate mean intensity (should be low for good segmentation, but > 0)
        output["diff_mean_intensity"] = float(np.mean(arr))
        
        # Check if it looks like a binary comparison result (mostly 0 and 255)
        unique_vals = np.unique(arr)
        if len(unique_vals) <= 2: # strict binary
             output["diff_is_binary"] = True
        elif len(unique_vals) < 10: # allowing for some anti-aliasing or slight noise
             output["diff_is_binary"] = True
             
    except Exception as e:
        print(f"Error analyzing image: {e}")

# Analyze Metrics CSV
if os.path.exists("$METRICS_FILE"):
    output["metrics_file_exists"] = True
    try:
        with open("$METRICS_FILE", 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            output["metrics_row_count"] = len(rows)
            
            # Check for Mean column
            if rows and any(k.lower().strip() == 'mean' for k in rows[0].keys()):
                output["metrics_has_mean"] = True
                # Try to grab the value
                for k, v in rows[0].items():
                    if k.lower().strip() == 'mean':
                        output["metrics_mean_value"] = float(v)
                        break
    except Exception as e:
        print(f"Error parsing CSV: {e}")

# Save JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Export analysis complete.")
PYEOF

echo "Result JSON generated at /tmp/task_result.json"