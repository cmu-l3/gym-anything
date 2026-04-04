#!/bin/bash
echo "=== Exporting Local Thickness Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/Fiji_Data/results/thickness"
RESULT_JSON="/tmp/thickness_result.json"

# Take final screenshot for evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to analyze output files and generate a comprehensive JSON report
python3 << PYEOF
import os
import json
import csv
import sys
import numpy as np
from PIL import Image

results_dir = "$RESULTS_DIR"
task_start = int("$TASK_START")

output = {
    "task_start": task_start,
    "files": {},
    "csv_data": [],
    "checks": {
        "solid_map_valid": False,
        "void_map_valid": False,
        "csv_valid": False,
        "viz_exists": False,
        "hist_exists": False
    }
}

def get_file_info(filename):
    path = os.path.join(results_dir, filename)
    if not os.path.exists(path):
        return {"exists": False}
    
    stats = os.stat(path)
    created_during_task = stats.st_mtime > task_start
    return {
        "exists": True,
        "size": stats.st_size,
        "created_during_task": created_during_task,
        "path": path
    }

# 1. Analyze Thickness Maps (TIFF)
# Local Thickness output should be 32-bit float (Mode 'F')
for map_type in ["solid_phase_thickness_map.tif", "void_phase_thickness_map.tif"]:
    info = get_file_info(map_type)
    is_valid = False
    stats = {}
    
    if info["exists"]:
        try:
            img = Image.open(info["path"])
            info["mode"] = img.mode
            
            # Convert to numpy to check values
            arr = np.array(img)
            info["dtype"] = str(arr.dtype)
            
            # Check if it looks like a distance map (float values, not just 0/255)
            # Local thickness returns float radii/diameters
            if arr.max() > 0:
                stats["max"] = float(arr.max())
                stats["mean"] = float(arr.mean())
                # Validity check: 32-bit float AND meaningful values
                if (img.mode == 'F' or arr.dtype == np.float32) and stats["max"] > 1.0:
                    is_valid = True
            
            info["stats"] = stats
        except Exception as e:
            info["error"] = str(e)
            
    output["files"][map_type] = info
    if map_type == "solid_phase_thickness_map.tif":
        output["checks"]["solid_map_valid"] = is_valid
    else:
        output["checks"]["void_map_valid"] = is_valid

# 2. Analyze CSV
csv_name = "thickness_statistics.csv"
csv_info = get_file_info(csv_name)
output["files"][csv_name] = csv_info

if csv_info["exists"]:
    try:
        with open(csv_info["path"], 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            output["csv_data"] = rows
            
            # minimal validation: 2 rows, required columns
            required = ["phase", "mean_thickness_px", "max_thickness_px"]
            if len(rows) >= 2 and all(col in reader.fieldnames for col in required):
                output["checks"]["csv_valid"] = True
    except Exception as e:
        csv_info["error"] = str(e)

# 3. Analyze Visualization Images
for viz in ["thickness_visualization.png", "thickness_histogram.png"]:
    info = get_file_info(viz)
    output["files"][viz] = info
    
    if info["exists"] and info["size"] > 1024: # > 1KB
        if "visualization" in viz:
            output["checks"]["viz_exists"] = True
        else:
            output["checks"]["hist_exists"] = True

# Write Result
with open("$RESULT_JSON", 'w') as f:
    json.dump(output, f, indent=2)

PYEOF

# Fix permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Export complete. JSON saved to $RESULT_JSON"