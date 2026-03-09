#!/bin/bash
# Export script for CTCF Quantification task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting CTCF Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python to parse the CSV robustly
python3 << 'PYEOF'
import json
import csv
import os
import io
import re

result_file = "/home/ga/ImageJ_Data/results/ctcf_results.csv"
task_start_file = "/tmp/task_start_timestamp"
output_json = "/tmp/ctcf_quantification_result.json"

output = {
    "file_exists": False,
    "file_valid_csv": False,
    "row_count": 0,
    "columns": [],
    "data": [],
    "background_value": None,
    "task_start_timestamp": 0,
    "file_modified_time": 0
}

# Get task start time
try:
    with open(task_start_file, 'r') as f:
        output["task_start_timestamp"] = int(f.read().strip())
except:
    pass

if os.path.exists(result_file):
    output["file_exists"] = True
    output["file_modified_time"] = int(os.path.getmtime(result_file))
    
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        # Parse CSV
        # Handle flexible delimiters just in case (comma, tab, semicolon)
        dialect = 'excel'
        if '\t' in content:
            dialect = 'excel-tab'
        elif ';' in content:
            # Register semi-colon dialect if needed, or just replace
            content = content.replace(';', ',')
            
        reader = csv.DictReader(io.StringIO(content), dialect=dialect)
        output["columns"] = reader.fieldnames or []
        
        rows = list(reader)
        output["row_count"] = len(rows)
        
        # Extract numerical data for verification
        # We need to normalize column names because agents might name them differently
        # e.g., "Integrated Density", "IntDen", "RawIntDen", "Area", "CTCF", "Background"
        
        for row in rows:
            clean_row = {}
            for k, v in row.items():
                if not k: continue
                key_lower = k.lower().strip()
                val_clean = str(v).strip()
                
                try:
                    val_num = float(val_clean)
                except ValueError:
                    val_num = val_clean # Keep as string if not number
                
                # Normalize keys
                if any(x in key_lower for x in ['area', 'size']):
                    clean_row['area'] = val_num
                elif any(x in key_lower for x in ['intden', 'integrated', 'rawintden']):
                    clean_row['intden'] = val_num
                elif 'ctcf' in key_lower:
                    clean_row['ctcf'] = val_num
                elif any(x in key_lower for x in ['back', 'bg', 'bkg']):
                    clean_row['background'] = val_num
                else:
                    clean_row[k] = val_num
            
            output["data"].append(clean_row)
            
        output["file_valid_csv"] = True
        
        # Try to find a global background value if not in rows
        # Sometimes agents put it in a separate row or file, but if they follow instructions
        # it should be in the table. If they put it in a "Background" column, we have it.
        
    except Exception as e:
        output["error"] = str(e)

with open(output_json, 'w') as f:
    json.dump(output, f, indent=2)

print(f"Export complete. File exists: {output['file_exists']}, Rows: {output['row_count']}")
PYEOF

echo "=== Export Complete ==="