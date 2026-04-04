#!/bin/bash
# Export script for Line Profile FWHM task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Line Profile FWHM Result ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

RESULT_FILE="/home/ga/ImageJ_Data/results/fwhm_measurements.csv"
START_TIME_FILE="/tmp/task_start_timestamp"

# Use Python to parse the CSV safely and generate a JSON report
python3 << 'PYEOF'
import json
import csv
import os
import io
import sys
import statistics

result_file = "/home/ga/ImageJ_Data/results/fwhm_measurements.csv"
start_time_file = "/tmp/task_start_timestamp"
output_json = "/tmp/line_profile_fwhm_result.json"

output = {
    "file_exists": False,
    "file_created_during_task": False,
    "row_count": 0,
    "fwhm_values": [],
    "peak_values": [],
    "bg_values": [],
    "has_summary": False,
    "mean_fwhm_reported": None,
    "valid_fwhm_count": 0,
    "peak_gt_bg_count": 0,
    "columns": [],
    "parse_error": None
}

# Check file existence and timestamp
if os.path.isfile(result_file):
    output["file_exists"] = True
    
    # Check timestamp
    try:
        with open(start_time_file, 'r') as f:
            start_time = float(f.read().strip())
        file_mtime = os.path.getmtime(result_file)
        if file_mtime > start_time:
            output["file_created_during_task"] = True
    except Exception:
        pass # Default to False if timestamps fail

    # Parse content
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        reader = csv.DictReader(io.StringIO(content))
        rows = list(reader)
        output["columns"] = reader.fieldnames or []
        
        # Identify columns loosely
        col_map = {}
        if reader.fieldnames:
            for col in reader.fieldnames:
                c = col.lower()
                if 'fwhm' in c or 'width' in c: col_map['fwhm'] = col
                elif 'peak' in c or 'max' in c: col_map['peak'] = col
                elif 'back' in c or 'bg' in c: col_map['bg'] = col
        
        data_rows = []
        summary_rows = []
        
        # Separate data from summary lines
        for row in rows:
            # Check if it's a summary row (often has 'Mean' or 'SD' in first column)
            first_val = str(list(row.values())[0]).lower() if row else ""
            if any(k in first_val for k in ['mean', 'avg', 'sd', 'std', 'dev']):
                summary_rows.append(row)
            else:
                data_rows.append(row)
        
        output["row_count"] = len(data_rows)
        output["has_summary"] = len(summary_rows) > 0
        
        # Extract values
        for row in data_rows:
            try:
                # FWHM
                if 'fwhm' in col_map:
                    val = float(row[col_map['fwhm']])
                    output["fwhm_values"].append(val)
                    if 8.0 <= val <= 60.0:
                        output["valid_fwhm_count"] += 1
                
                # Peak & Background
                peak = -1
                bg = 9999
                if 'peak' in col_map:
                    peak = float(row[col_map['peak']])
                    output["peak_values"].append(peak)
                if 'bg' in col_map:
                    bg = float(row[col_map['bg']])
                    output["bg_values"].append(bg)
                
                if peak > bg and peak > 0:
                    output["peak_gt_bg_count"] += 1
                    
            except (ValueError, TypeError):
                pass
                
    except Exception as e:
        output["parse_error"] = str(e)

# Write JSON output
with open(output_json, 'w') as f:
    json.dump(output, f, indent=2)

print(f"Exported JSON info: Exists={output['file_exists']}, Rows={output['row_count']}")
PYEOF

echo "=== Export Complete ==="