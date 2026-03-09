#!/bin/bash
# Export script for threshold_method_comparison task
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Threshold Comparison Results ==="

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Define paths
RESULT_FILE="/home/ga/ImageJ_Data/results/threshold_comparison.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_JSON="/tmp/task_result.json"

# 3. Analyze Result File using Python
# We use Python for robust CSV parsing and logic
python3 << PYEOF
import json
import os
import csv
import time

result_path = "$RESULT_FILE"
task_start = int("$TASK_START")
output = {
    "file_exists": False,
    "file_created_during_task": False,
    "row_count": 0,
    "methods": [],
    "thresholds": [],
    "counts": [],
    "areas": [],
    "distinct_thresholds": 0,
    "valid_format": False,
    "error": None
}

if os.path.exists(result_path):
    output["file_exists"] = True
    
    # Check modification time
    mtime = os.path.getmtime(result_path)
    if mtime > task_start:
        output["file_created_during_task"] = True
    
    try:
        with open(result_path, 'r', encoding='utf-8') as f:
            # Read snippet for logging
            content = f.read(1024)
            f.seek(0)
            
            # Use DictReader for flexibility, but handle header variations
            # We look for keywords in the header
            header_line = f.readline().lower()
            f.seek(0)
            
            has_method = any(x in header_line for x in ['method', 'algo', 'name'])
            has_thresh = any(x in header_line for x in ['thresh', 'value', 'level'])
            has_count = any(x in header_line for x in ['count', 'number', 'objects', 'particle'])
            has_area = any(x in header_line for x in ['area', 'total', 'size'])
            
            if has_method and has_thresh:
                output["valid_format"] = True
                reader = csv.reader(f)
                next(reader) # Skip header
                
                for row in reader:
                    if len(row) < 2: continue
                    
                    # Store raw values
                    output["row_count"] += 1
                    output["methods"].append(row[0].strip())
                    
                    # Try parsing numbers
                    try:
                        # Assume col 1 is threshold, col 2 is count (heuristic)
                        # The user prompt specified: Method, Threshold, Count, Total_Area
                        # We try to be flexible if they swapped columns 2 and 3
                        t_val = float(row[1])
                        output["thresholds"].append(t_val)
                        
                        if len(row) > 2:
                            output["counts"].append(float(row[2]))
                        if len(row) > 3:
                            output["areas"].append(float(row[3]))
                    except ValueError:
                        pass
            
            # Calculate distinct thresholds (proxy for "did they actually use different methods?")
            # Rounding to handle potential float variations, though thresholds are usually ints
            unique_t = set(int(t) for t in output["thresholds"])
            output["distinct_thresholds"] = len(unique_t)

    except Exception as e:
        output["error"] = str(e)

# 4. Save analysis to JSON
with open("$OUTPUT_JSON", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export analysis saved to $OUTPUT_JSON")
PYEOF

# 4. Permissions check
chmod 666 "$OUTPUT_JSON" 2>/dev/null || true

echo "=== Export Complete ==="
cat "$OUTPUT_JSON"