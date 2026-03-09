#!/bin/bash
# Export script for intracellular_distribution_edm task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Task Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Result File
RESULT_FILE="/home/ga/ImageJ_Data/results/vesicle_distribution.csv"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Python script to parse CSV and validation metrics
python3 << 'PYEOF'
import json
import csv
import os
import sys
import statistics

result_file = "/home/ga/ImageJ_Data/results/vesicle_distribution.csv"
task_start_ts = int(open("/tmp/task_start_timestamp").read().strip())

output = {
    "file_exists": False,
    "file_valid_timestamp": False,
    "row_count": 0,
    "columns": [],
    "mean_values": [],
    "median_value": 0,
    "mean_of_means": 0,
    "min_value": 0,
    "max_value": 0,
    "has_mean_column": False
}

if os.path.exists(result_file):
    output["file_exists"] = True
    mtime = os.path.getmtime(result_file)
    if mtime > task_start_ts:
        output["file_valid_timestamp"] = True
    
    try:
        with open(result_file, 'r') as f:
            reader = csv.DictReader(f)
            output["columns"] = reader.fieldnames if reader.fieldnames else []
            
            # Check for Mean column (could be "Mean", "Mean1", "Mean_Gray_Value")
            mean_col = next((c for c in output["columns"] if "Mean" in c), None)
            
            if mean_col:
                output["has_mean_column"] = True
                values = []
                for row in reader:
                    try:
                        val = float(row[mean_col])
                        values.append(val)
                    except ValueError:
                        pass
                
                output["row_count"] = len(values)
                output["mean_values"] = values # Sending all values might be large, but useful for verifier
                
                if values:
                    output["mean_of_means"] = statistics.mean(values)
                    output["median_value"] = statistics.median(values)
                    output["min_value"] = min(values)
                    output["max_value"] = max(values)
            else:
                # Just count rows if no mean column
                output["row_count"] = sum(1 for row in reader)

    except Exception as e:
        output["error"] = str(e)

# Save analysis to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f)

PYEOF

echo "Export complete. Result saved to /tmp/task_result.json"