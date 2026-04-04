#!/bin/bash
# Export script for Z-Axis Nuclear Depth task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Z-Axis Analysis Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Define Paths
RESULTS_DIR="/home/ga/ImageJ_Data/results"
CSV_FILE="$RESULTS_DIR/nucleus_depth.csv"
TIF_FILE="$RESULTS_DIR/nucleus_reslice.tif"
TASK_START_FILE="/tmp/task_start_time"

# 3. Analyze output files using Python
# We extract: file existence, timestamps, CSV value, TIF dimensions
python3 << 'PYEOF'
import json
import os
import csv
import sys
from PIL import Image

output = {
    "csv_exists": False,
    "tif_exists": False,
    "csv_created_during_task": False,
    "tif_created_during_task": False,
    "measured_value": 0.0,
    "reslice_width": 0,
    "reslice_height": 0,
    "errors": []
}

csv_path = "/home/ga/ImageJ_Data/results/nucleus_depth.csv"
tif_path = "/home/ga/ImageJ_Data/results/nucleus_reslice.tif"
start_time_path = "/tmp/task_start_time"

# Get start time
task_start = 0
try:
    with open(start_time_path, 'r') as f:
        task_start = int(f.read().strip())
except Exception as e:
    output["errors"].append(f"Could not read start time: {e}")

# Check CSV
if os.path.exists(csv_path):
    output["csv_exists"] = True
    if os.path.getmtime(csv_path) > task_start:
        output["csv_created_during_task"] = True
    
    try:
        # ImageJ Results table usually has headings like " ", "Area", "Mean", "Length", etc.
        # Or simply "Length" if using Measure tool on a line
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            if rows:
                last_row = rows[-1]
                # Look for typical length/height columns
                for col in ['Length', 'Height', 'Y', 'Mean']:
                    if col in last_row:
                        try:
                            val = float(last_row[col])
                            # If it's a line measurement, Length is the key one
                            if col == 'Length': 
                                output["measured_value"] = val
                                break
                            # Fallback
                            output["measured_value"] = val
                        except ValueError:
                            pass
                
                # If DictReader failed to find specific columns, try raw last value
                if output["measured_value"] == 0.0 and len(rows) > 0:
                     # Heuristic: sometimes simple lists just have the value
                     pass
    except Exception as e:
        output["errors"].append(f"CSV parse error: {e}")

# Check TIF
if os.path.exists(tif_path):
    output["tif_exists"] = True
    if os.path.getmtime(tif_path) > task_start:
        output["tif_created_during_task"] = True
    
    try:
        with Image.open(tif_path) as img:
            output["reslice_width"] = img.width
            output["reslice_height"] = img.height
    except Exception as e:
        output["errors"].append(f"Image read error: {e}")

# Write result
with open("/tmp/z_axis_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Export logic complete.")
PYEOF

echo "=== Export Complete ==="
cat /tmp/z_axis_result.json