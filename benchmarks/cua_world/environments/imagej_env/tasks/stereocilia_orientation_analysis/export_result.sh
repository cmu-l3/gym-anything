#!/bin/bash
# Export script for Stereocilia Orientation Analysis task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Orientation Analysis Result ==="

# Take final screenshot of the state
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Define paths
RESULT_FILE="/home/ga/ImageJ_Data/results/directionality_results.csv"
TASK_START_FILE="/tmp/task_start_timestamp"
JSON_OUTPUT="/tmp/stereocilia_orientation_analysis_result.json"

# Python script to parse the CSV and metadata robustly
python3 << 'PYEOF'
import json
import csv
import os
import io
import re
import sys

result_file = "/home/ga/ImageJ_Data/results/directionality_results.csv"
task_start_file = "/tmp/task_start_timestamp"
output_file = "/tmp/stereocilia_orientation_analysis_result.json"

output = {
    "file_exists": False,
    "file_created_during_task": False,
    "histogram_rows": 0,
    "angular_range": 0,
    "has_amount_values": False,
    "preferred_direction": None,
    "dispersion": None,
    "goodness": None,
    "parse_error": None
}

try:
    # 1. Check file existence and timestamp
    if os.path.isfile(result_file):
        output["file_exists"] = True
        
        # Check modification time against task start
        try:
            with open(task_start_file, 'r') as f:
                task_start = int(f.read().strip())
            file_mtime = int(os.path.getmtime(result_file))
            if file_mtime > task_start:
                output["file_created_during_task"] = True
        except Exception:
            # If timestamp check fails, default to True if file exists (verifier will handle strictness if needed)
            pass

        # 2. Parse Content
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        content_lower = content.lower()
        lines = [l.strip() for l in content.split('\n') if l.strip()]
        
        # Strategy A: Look for summary stats in key-value format or labeled columns
        # Patterns for Preferred Direction
        dir_match = re.search(r'(preferred|peak|direction|angle).*?([+-]?\d+\.?\d*)', content_lower)
        if dir_match:
            try:
                output["preferred_direction"] = float(dir_match.group(2))
            except:
                pass
                
        # Patterns for Dispersion
        disp_match = re.search(r'(dispersion|spread|std).*?(\d+\.?\d*)', content_lower)
        if disp_match:
            try:
                output["dispersion"] = float(disp_match.group(2))
            except:
                pass

        # Strategy B: Parse Histogram Data
        # We look for tabular data with at least 2 columns of numbers
        # Column 1 should look like angles (-90 to 90 or 0 to 180 or 0 to 360)
        # Column 2 should look like counts/frequencies (0.0 to 1.0 or integers)
        
        histogram_angles = []
        histogram_amounts = []
        
        try:
            # Use CSV reader
            reader = csv.reader(io.StringIO(content))
            for row in reader:
                if len(row) < 2:
                    continue
                
                # Try to convert first two columns to numbers
                try:
                    val1 = float(str(row[0]).strip())
                    val2 = float(str(row[1]).strip())
                    
                    # Heuristic: Angles are usually typically between -180 and 360
                    # Amounts are positive
                    if -360 <= val1 <= 360 and val2 >= 0:
                        histogram_angles.append(val1)
                        histogram_amounts.append(val2)
                except ValueError:
                    continue
        except Exception as e:
            output["parse_error"] = str(e)

        output["histogram_rows"] = len(histogram_angles)
        
        if histogram_angles:
            output["angular_range"] = max(histogram_angles) - min(histogram_angles)
            
        if histogram_amounts and any(v > 0 for v in histogram_amounts):
            # Check if they are not all identical (trivial output)
            if len(set(histogram_amounts)) > 1:
                output["has_amount_values"] = True

except Exception as e:
    output["parse_error"] = str(e)

with open(output_file, 'w') as f:
    json.dump(output, f, indent=2)

print("Export complete.")
PYEOF

echo "Result JSON generated at $JSON_OUTPUT"
cat "$JSON_OUTPUT"