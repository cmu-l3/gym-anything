#!/bin/bash
# Export script for Watershed Segmentation task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Watershed Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Paths
CSV_FILE="/home/ga/ImageJ_Data/results/watershed_measurements.csv"
TXT_FILE="/home/ga/ImageJ_Data/results/watershed_summary.txt"
TIMESTAMP_FILE="/tmp/task_start_timestamp"

# Use Python to parse results robustly
python3 << 'PYEOF'
import json
import csv
import os
import re
import sys

csv_path = "/home/ga/ImageJ_Data/results/watershed_measurements.csv"
txt_path = "/home/ga/ImageJ_Data/results/watershed_summary.txt"
ts_path = "/tmp/task_start_timestamp"

output = {
    "csv_exists": False,
    "txt_exists": False,
    "csv_modified_time": 0,
    "txt_modified_time": 0,
    "task_start_time": 0,
    "csv_row_count": 0,
    "valid_area_count": 0,
    "summary_before_count": -1,
    "summary_after_count": -1,
    "summary_diff": 0,
    "parse_error": None
}

# Load task start time
try:
    if os.path.exists(ts_path):
        output["task_start_time"] = int(open(ts_path).read().strip())
except:
    pass

# Parse CSV
if os.path.exists(csv_path):
    output["csv_exists"] = True
    output["csv_modified_time"] = int(os.path.getmtime(csv_path))
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            # Try parsing with csv module
            try:
                reader = csv.DictReader(content.splitlines())
                rows = list(reader)
                output["csv_row_count"] = len(rows)
                
                # Check for Area column and valid values
                for row in rows:
                    for k, v in row.items():
                        if k and 'area' in k.lower():
                            try:
                                val = float(v)
                                if 10 <= val <= 8000:
                                    output["valid_area_count"] += 1
                            except:
                                pass
            except:
                # Fallback: simple line count if CSV structure is broken
                lines = [l for l in content.splitlines() if l.strip()]
                output["csv_row_count"] = max(0, len(lines) - 1)
                
    except Exception as e:
        output["parse_error"] = f"CSV Error: {str(e)}"

# Parse Summary Text
if os.path.exists(txt_path):
    output["txt_exists"] = True
    output["txt_modified_time"] = int(os.path.getmtime(txt_path))
    try:
        with open(txt_path, 'r', encoding='utf-8', errors='replace') as f:
            text = f.read()
            
            # Look for numbers in the text
            # Users might write "Before: 30, After: 60" or similar
            # We look for patterns or just extract all numbers
            
            # Simple heuristic: look for lines containing "before" and "after"
            # or extract numbers and assume smaller is before, larger is after (if reasonable context)
            
            nums = [int(x) for x in re.findall(r'\b\d+\b', text)]
            
            # Specific parsing
            before_match = re.search(r'before.*?(\d+)', text, re.IGNORECASE)
            after_match = re.search(r'after.*?(\d+)', text, re.IGNORECASE)
            
            if before_match:
                output["summary_before_count"] = int(before_match.group(1))
            if after_match:
                output["summary_after_count"] = int(after_match.group(1))
                
            # Fallback if regex failed but we have numbers
            if output["summary_before_count"] == -1 and len(nums) >= 2:
                # Assuming standard task flow: usually mention before then after
                # But safer to check context. If failed, just report what we found
                pass

    except Exception as e:
        output["parse_error"] = f"TXT Error: {str(e)}"

with open("/tmp/watershed_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Exported JSON: csv_rows={output['csv_row_count']}, before={output['summary_before_count']}, after={output['summary_after_count']}")
PYEOF

# Move to final location
cp /tmp/watershed_result.json /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="