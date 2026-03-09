#!/bin/bash
# Export script for temporal_change_detection task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Temporal Change Detection Result ==="

RESULTS_DIR="/home/ga/ImageJ_Data/results"
TASK_START_FILE="/tmp/task_start_timestamp"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Python script to analyze results and package into JSON
python3 << 'PYEOF'
import json
import os
import csv
import glob

results_dir = "/home/ga/ImageJ_Data/results"
task_start_file = "/tmp/task_start_timestamp"
output_json_path = "/tmp/temporal_change_result.json"

output = {
    "files_found": {},
    "csv_data": [],
    "timestamps_valid": True,
    "task_start_time": 0
}

# Read task start time
try:
    with open(task_start_file, 'r') as f:
        output["task_start_time"] = int(f.read().strip())
except:
    output["timestamps_valid"] = False

# Check expected files
expected_files = ["spindle_start.tif", "spindle_end.tif", "change_map.tif", "change_quantification.csv"]

for fname in expected_files:
    fpath = os.path.join(results_dir, fname)
    if os.path.exists(fpath):
        mtime = int(os.path.getmtime(fpath))
        size = os.path.getsize(fpath)
        valid_time = mtime >= output["task_start_time"]
        
        output["files_found"][fname] = {
            "exists": True,
            "size": size,
            "mtime": mtime,
            "valid_time": valid_time
        }
        if not valid_time:
            output["timestamps_valid"] = False
    else:
        output["files_found"][fname] = {
            "exists": False
        }

# Parse CSV content if exists
csv_path = os.path.join(results_dir, "change_quantification.csv")
if os.path.exists(csv_path):
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
            # Read all content first to handle potential malformed CSVs from ImageJ
            content = f.read()
            # Basic parsing looking for headers and numeric data
            lines = [l.strip() for l in content.split('\n') if l.strip()]
            output["csv_content_raw"] = content
            
            # Try proper CSV parsing
            import io
            reader = csv.DictReader(io.StringIO(content))
            output["csv_data"] = list(reader)
    except Exception as e:
        output["csv_error"] = str(e)

with open(output_json_path, "w") as f:
    json.dump(output, f, indent=2)

print("Export JSON created.")
PYEOF

echo "=== Export Complete ==="