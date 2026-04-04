#!/bin/bash
echo "=== Exporting Focus Quality Assessment results ==="

RESULT_FILE="/home/ga/ImageJ_Data/results/focus_quality_report.csv"
OUTPUT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
IMAGE_LIST="/tmp/focus_image_list.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence
FILE_EXISTS="false"
FILE_SIZE="0"
CREATED_AFTER="false"

# Locate file (handle case-sensitivity or slight misnaming)
ACTUAL_FILE=""
if [ -f "$RESULT_FILE" ]; then
    ACTUAL_FILE="$RESULT_FILE"
elif [ -f "/home/ga/ImageJ_Data/results/Results.csv" ]; then
    # Accept standard Results.csv if user forgot to rename
    ACTUAL_FILE="/home/ga/ImageJ_Data/results/Results.csv"
fi

if [ -n "$ACTUAL_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$ACTUAL_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$ACTUAL_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_AFTER="true"
    fi
fi

# Python script to parse CSV and produce JSON
python3 << PYEOF
import csv
import json
import os
import statistics

result_file = "$ACTUAL_FILE"
output_json = "$OUTPUT_JSON"
task_start = int("$TASK_START")
file_exists = "$FILE_EXISTS" == "true"
created_after = "$CREATED_AFTER" == "true"
file_size = int("$FILE_SIZE")

result = {
    "file_exists": file_exists,
    "created_after_start": created_after,
    "file_size": file_size,
    "row_count": 0,
    "has_header": False,
    "has_stddev": False,
    "has_mean": False,
    "is_sorted_desc": False,
    "stddev_diversity": 0.0,
    "all_stddev_positive": False,
    "filenames_match": 0
}

try:
    if file_exists and file_size > 0:
        with open(result_file, 'r', errors='replace') as f:
            content = f.read().strip()
            
        lines = content.split('\n')
        if len(lines) > 1:
            # Detect delimiter
            delimiter = ','
            if '\t' in lines[0] and ',' not in lines[0]:
                delimiter = '\t'
                
            reader = csv.reader(lines, delimiter=delimiter)
            rows = list(reader)
            
            if len(rows) > 0:
                header = [h.lower().strip() for h in rows[0]]
                data = rows[1:]
                result["has_header"] = True
                result["row_count"] = len(data)
                
                # Identify columns
                std_idx = -1
                mean_idx = -1
                name_idx = -1
                
                for i, h in enumerate(header):
                    if any(x in h for x in ['std', 'dev', 'sd']):
                        std_idx = i
                    if any(x in h for x in ['mean', 'avg']):
                        mean_idx = i
                    if any(x in h for x in ['file', 'name', 'label', 'image']):
                        name_idx = i
                
                if std_idx != -1:
                    result["has_stddev"] = True
                    # Extract values
                    std_values = []
                    for r in data:
                        if len(r) > std_idx:
                            try:
                                val = float(r[std_idx])
                                std_values.append(val)
                            except ValueError:
                                pass
                    
                    if std_values:
                        # Check positivity
                        result["all_stddev_positive"] = all(v > 0 for v in std_values)
                        
                        # Check diversity (std of stddevs > 0.5)
                        if len(std_values) > 1:
                            result["stddev_diversity"] = statistics.stdev(std_values)
                            
                        # Check sorting (descending)
                        # Allow 1 swap tolerance for nearly sorted lists
                        is_sorted = True
                        swaps = 0
                        for i in range(len(std_values) - 1):
                            if std_values[i] < std_values[i+1]:
                                swaps += 1
                        
                        if swaps <= 1:
                            result["is_sorted_desc"] = True
                            
                if mean_idx != -1:
                    result["has_mean"] = True

                # Check filename matching if possible
                if name_idx != -1:
                    match_count = 0
                    try:
                        with open("$IMAGE_LIST", 'r') as f:
                            expected_files = [l.strip() for l in f.readlines()]
                        
                        for r in data:
                            if len(r) > name_idx:
                                val = r[name_idx]
                                if any(exp in val for exp in expected_files) or \
                                   any(val in exp for exp in expected_files):
                                    match_count += 1
                    except:
                        pass
                    result["filenames_match"] = match_count

except Exception as e:
    result["error"] = str(e)

with open(output_json, 'w') as f:
    json.dump(result, f)
PYEOF

echo "Result exported to $OUTPUT_JSON"
cat "$OUTPUT_JSON"