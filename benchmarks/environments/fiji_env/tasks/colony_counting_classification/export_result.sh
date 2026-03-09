#!/bin/bash
echo "=== Exporting Colony Counting Results ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather file stats
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Fiji_Data/results/colonies"

MEASUREMENTS_FILE="$RESULTS_DIR/colony_measurements.csv"
SUMMARY_FILE="$RESULTS_DIR/colony_summary.txt"
DISTRIBUTION_FILE="$RESULTS_DIR/size_distribution.csv"
OVERLAY_FILE="$RESULTS_DIR/colony_overlay.png"

# Python script to parse results and generate JSON
python3 <<EOF
import json
import os
import csv
import sys

results_dir = "$RESULTS_DIR"
task_start = int("$TASK_START")

output = {
    "files": {},
    "data": {
        "colony_count": 0,
        "has_classification": False,
        "size_classes_found": [],
        "summary_content_valid": False,
        "distribution_valid": False
    },
    "timestamp_valid": True
}

def check_file(path):
    if not os.path.exists(path):
        return {"exists": False}
    stats = os.stat(path)
    return {
        "exists": True,
        "size": stats.st_size,
        "mtime": stats.st_mtime,
        "created_after_start": stats.st_mtime > task_start
    }

# Check all files
files_to_check = {
    "measurements": "$MEASUREMENTS_FILE",
    "summary": "$SUMMARY_FILE",
    "distribution": "$DISTRIBUTION_FILE",
    "overlay": "$OVERLAY_FILE"
}

for key, path in files_to_check.items():
    output["files"][key] = check_file(path)
    if output["files"][key]["exists"] and not output["files"][key]["created_after_start"]:
        output["timestamp_valid"] = False

# Parse Measurements CSV
measurements_info = output["files"]["measurements"]
if measurements_info["exists"] and measurements_info["size"] > 0:
    try:
        with open("$MEASUREMENTS_FILE", 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            output["data"]["colony_count"] = len(rows)
            
            if rows:
                headers = [h.lower() for h in reader.fieldnames]
                # Check for size classification column (flexible naming)
                class_cols = [h for h in headers if 'class' in h or 'category' in h or 'size' in h]
                # Also check if it's implicitly there (e.g. data implies it)
                
                # Check if rows have 'small', 'medium', 'large' values in any column
                found_classes = set()
                for row in rows:
                    for val in row.values():
                        val_str = str(val).lower()
                        if 'small' in val_str: found_classes.add('small')
                        if 'medium' in val_str: found_classes.add('medium')
                        if 'large' in val_str: found_classes.add('large')
                
                output["data"]["size_classes_found"] = list(found_classes)
                output["data"]["has_classification"] = len(found_classes) >= 1
    except Exception as e:
        output["data"]["error_measurements"] = str(e)

# Parse Summary Text
summary_info = output["files"]["summary"]
if summary_info["exists"] and summary_info["size"] > 0:
    try:
        with open("$SUMMARY_FILE", 'r') as f:
            content = f.read().lower()
            # Check for keywords
            has_count = any(x in content for x in ['count', 'total', 'number'])
            has_classes = all(x in content for x in ['small', 'medium', 'large'])
            output["data"]["summary_content_valid"] = has_count and has_classes
    except Exception as e:
        output["data"]["error_summary"] = str(e)

# Parse Distribution CSV
dist_info = output["files"]["distribution"]
if dist_info["exists"] and dist_info["size"] > 0:
    try:
        with open("$DISTRIBUTION_FILE", 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            # Should have roughly 3 rows (small, medium, large)
            if len(rows) >= 3:
                output["data"]["distribution_valid"] = True
    except Exception as e:
        output["data"]["error_distribution"] = str(e)

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)

EOF

# Move result to safe location and ensure permissions
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json