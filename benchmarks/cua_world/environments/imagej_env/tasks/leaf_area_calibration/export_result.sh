#!/bin/bash
# Export script for Leaf Area Calibration task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Leaf Area Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

RESULT_FILE="/home/ga/ImageJ_Data/results/leaf_area.csv"
TASK_START_FILE="/tmp/task_start_timestamp"

# We use python to parse the CSV robustly and check timestamps
python3 << 'PYEOF'
import json
import csv
import os
import io
import re

result_file = "/home/ga/ImageJ_Data/results/leaf_area.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_created_during_task": False,
    "measured_area": None,
    "unit_inferred": "unknown",
    "raw_value": None,
    "parse_error": None
}

# 1. Check Task Start Time
try:
    with open(task_start_file, 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

# 2. Check Result File
if os.path.isfile(result_file):
    output["file_exists"] = True
    mtime = int(os.path.getmtime(result_file))
    
    if mtime > task_start:
        output["file_created_during_task"] = True
    
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        # Parse CSV
        reader = csv.DictReader(io.StringIO(content))
        rows = list(reader)
        
        if rows:
            # Look for Area column (case insensitive)
            area_val = None
            for col, val in rows[0].items():
                if col and "area" in col.lower():
                    try:
                        area_val = float(val)
                        break
                    except ValueError:
                        continue
            
            # Fallback: if no named column, take first numeric column
            if area_val is None:
                 for val in rows[0].values():
                     try:
                         area_val = float(val)
                         break
                     except ValueError:
                         continue

            output["raw_value"] = area_val

            if area_val is not None:
                output["measured_area"] = area_val
                
                # Infer unit based on magnitude
                # Uncalibrated (pixels) would be ~100,000+
                # Calibrated (cm^2) would be ~50
                if area_val > 10000:
                    output["unit_inferred"] = "pixels"
                elif 10 <= area_val <= 1000:
                    output["unit_inferred"] = "calibrated" # likely cm^2 or similar
                else:
                    output["unit_inferred"] = "other" # mm^2 or inches?

    except Exception as e:
        output["parse_error"] = str(e)

# 3. Save JSON result
with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export summary: Exists={output['file_exists']}, Area={output['measured_area']}, Unit={output['unit_inferred']}")
PYEOF

echo "=== Export Complete ==="