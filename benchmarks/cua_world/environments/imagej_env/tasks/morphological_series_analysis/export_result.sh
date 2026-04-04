#!/bin/bash
# Export script for Morphological Series Analysis

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Morphological Series Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

RESULT_FILE="/home/ga/ImageJ_Data/results/morphological_series.csv"
TASK_START_FILE="/tmp/task_start_timestamp"

# Create a Python script to robustly parse the CSV and check logic
# We use Python here to handle CSV parsing and logic checks more reliably than bash
python3 << 'PYEOF'
import json
import csv
import os
import io
import re
import sys

result_file = "/home/ga/ImageJ_Data/results/morphological_series.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_created_during_task": False,
    "row_count": 0,
    "columns_found": [],
    "conditions_found": [],
    "has_count": False,
    "has_area": False,
    "has_avg_size": False,
    "trend_erode_reduces_area": False,
    "trend_dilate_increases_area": False,
    "data_consistency_score": 0,
    "data": {}
}

# Check file existence and timestamp
if os.path.isfile(result_file):
    output["file_exists"] = True
    
    # Check timestamp
    try:
        task_start = int(open(task_start_file).read().strip())
        file_mtime = int(os.path.getmtime(result_file))
        if file_mtime > task_start:
            output["file_created_during_task"] = True
    except Exception:
        # If timestamp read fails, assume created during task if it exists now and didn't before
        # (The setup script deleted it)
        output["file_created_during_task"] = True

    # Parse content
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        # Detect delimiter (comma or tab)
        dialect = 'excel'
        if '\t' in content:
            dialect = 'excel-tab'
            
        reader = csv.DictReader(io.StringIO(content), dialect=dialect)
        rows = list(reader)
        output["row_count"] = len(rows)
        output["columns_found"] = reader.fieldnames or []
        
        # Normalize column names for checking
        lc_columns = [c.lower() for c in output["columns_found"]]
        output["has_count"] = any('count' in c or 'num' in c for c in lc_columns)
        output["has_area"] = any('total' in c and 'area' in c for c in lc_columns) or \
                             (any('area' in c for c in lc_columns) and not any('avg' in c for c in lc_columns))
        output["has_avg_size"] = any('avg' in c or 'mean' in c or 'size' in c for c in lc_columns)

        # Extract data for logic checks
        data_map = {}
        for row in rows:
            # Find the condition name (first column or column with "operation"/"name")
            name = ""
            for k, v in row.items():
                if any(x in k.lower() for x in ['operation', 'name', 'condition', 'type']):
                    name = v
                    break
            if not name and output["columns_found"]:
                name = row[output["columns_found"][0]] # Default to first col
            
            name_lower = str(name).lower()
            
            # Parse metrics
            metrics = {'area': 0.0, 'count': 0.0}
            for k, v in row.items():
                k_low = k.lower()
                try:
                    val = float(str(v).replace(',', '').strip())
                    if 'total' in k_low and 'area' in k_low:
                        metrics['area'] = val
                    elif 'area' in k_low and 'avg' not in k_low and metrics['area'] == 0:
                        metrics['area'] = val
                    elif 'count' in k_low or 'num' in k_low:
                        metrics['count'] = val
                except:
                    pass
            
            if 'original' in name_lower or 'base' in name_lower:
                data_map['original'] = metrics
            elif 'erode' in name_lower:
                data_map['erode'] = metrics
            elif 'dilate' in name_lower:
                data_map['dilate'] = metrics
            elif 'open' in name_lower:
                data_map['open'] = metrics
            elif 'close' in name_lower:
                data_map['close'] = metrics
                
            output["conditions_found"].append(name)

        output["data"] = data_map

        # Verify Logical Trends
        # Erosion should reduce total area
        if 'original' in data_map and 'erode' in data_map:
            if data_map['erode']['area'] < data_map['original']['area']:
                output["trend_erode_reduces_area"] = True
                
        # Dilation should increase total area
        if 'original' in data_map and 'dilate' in data_map:
            if data_map['dilate']['area'] > data_map['original']['area']:
                output["trend_dilate_increases_area"] = True
                
        # Consistency Check: Are values numeric and positive?
        consistent_rows = 0
        for k, v in data_map.items():
            if v['area'] > 0 and v['count'] > 0:
                consistent_rows += 1
        
        output["data_consistency_score"] = consistent_rows

    except Exception as e:
        output["error"] = str(e)

# Save to JSON
with open("/tmp/morphological_series_analysis_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Export finished.")
PYEOF

echo "=== Export Complete ==="