#!/bin/bash
# Export script for nuclear_cytoplasmic_ratio task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting N/C Ratio Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Define paths
RESULT_FILE="/home/ga/ImageJ_Data/results/nc_ratio_results.csv"
TASK_START_FILE="/tmp/task_start_timestamp"

# 3. Python script to analyze the CSV content and metadata
python3 << 'PYEOF'
import json
import csv
import os
import io
import re

result_file = "/home/ga/ImageJ_Data/results/nc_ratio_results.csv"
task_start_file = "/tmp/task_start_timestamp"
output_json = "/tmp/nuclear_cytoplasmic_ratio_result.json"

output = {
    "file_exists": False,
    "file_created_during_task": False,
    "row_count": 0,
    "columns": [],
    "has_nuclear_data": False,
    "has_cytoplasmic_data": False,
    "has_ratio_data": False,
    "consistent_ratios": False,
    "data_values": [],
    "errors": []
}

# Check file existence and timestamp
if os.path.exists(result_file):
    output["file_exists"] = True
    
    # Check timestamp
    try:
        task_start = int(open(task_start_file).read().strip())
        file_mtime = int(os.path.getmtime(result_file))
        if file_mtime > task_start:
            output["file_created_during_task"] = True
    except Exception as e:
        output["errors"].append(f"Timestamp check failed: {str(e)}")

    # Parse content
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        # Basic keyword check in raw content
        content_lower = content.lower()
        output["has_nuclear_data"] = any(k in content_lower for k in ['nuc', 'nucleus', 'nuclei'])
        output["has_cytoplasmic_data"] = any(k in content_lower for k in ['cyto', 'cytoplasm', 'cytoplasmic'])
        output["has_ratio_data"] = any(k in content_lower for k in ['ratio', 'n/c', 'fraction'])
        
        # CSV Parsing
        f_io = io.StringIO(content)
        reader = csv.DictReader(f_io)
        rows = list(reader)
        output["row_count"] = len(rows)
        output["columns"] = reader.fieldnames or []
        
        # Extract numeric values for validation
        valid_triplets = 0
        
        for row in rows:
            # Try to identify N, C, and Ratio values in this row
            n_val = None
            c_val = None
            r_val = None
            
            for col, val in row.items():
                if not val: continue
                col_norm = col.lower().strip()
                try:
                    num = float(str(val).strip())
                    
                    if any(x in col_norm for x in ['nuc']):
                        n_val = num
                    elif any(x in col_norm for x in ['cyto']):
                        c_val = num
                    elif any(x in col_norm for x in ['ratio', 'n/c']):
                        r_val = num
                except ValueError:
                    continue
            
            # Store found values
            entry = {"n": n_val, "c": c_val, "r": r_val}
            output["data_values"].append(entry)
            
            # Check mathematical consistency if we have all three
            if n_val is not None and c_val is not None and r_val is not None and c_val != 0:
                calc_ratio = n_val / c_val
                # Allow 10% tolerance (rounding differences)
                if abs(calc_ratio - r_val) / r_val < 0.1:
                    valid_triplets += 1
        
        if valid_triplets >= 1:
            output["consistent_ratios"] = True
            
    except Exception as e:
        output["errors"].append(f"CSV parsing failed: {str(e)}")

# Save verification JSON
with open(output_json, 'w') as f:
    json.dump(output, f, indent=2)

print(f"Analysis complete. File exists: {output['file_exists']}, Rows: {output['row_count']}")
PYEOF

echo "=== Export Complete ==="