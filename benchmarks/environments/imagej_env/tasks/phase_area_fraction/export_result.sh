#!/bin/bash
# Export script for phase_area_fraction task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Phase Area Fraction Results ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
RESULT_FILE="/home/ga/ImageJ_Data/results/phase_fractions.csv"
TASK_START_FILE="/tmp/task_start_timestamp"
OUTPUT_JSON="/tmp/task_result.json"

# Use Python to parse the CSV safely and create a structured JSON
python3 << 'PYEOF'
import json
import csv
import os
import io
import re
import sys

result_file = "/home/ga/ImageJ_Data/results/phase_fractions.csv"
task_start_file = "/tmp/task_start_timestamp"
output_json = "/tmp/task_result.json"

data = {
    "file_exists": False,
    "file_created_after_start": False,
    "row_count": 0,
    "phases_found": 0,
    "total_area_pixels": 0,
    "total_fraction_pct": 0.0,
    "columns": [],
    "raw_rows": [],
    "numeric_data": [],
    "valid_format": False
}

# 1. Check file existence and timestamp
if os.path.exists(result_file):
    data["file_exists"] = True
    
    # Check timestamp
    try:
        file_mtime = os.path.getmtime(result_file)
        with open(task_start_file, 'r') as f:
            start_time = float(f.read().strip())
        
        if file_mtime > start_time:
            data["file_created_after_start"] = True
    except Exception as e:
        print(f"Timestamp check error: {e}")

    # 2. Parse Content
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        
        # Try CSV parsing
        reader = csv.DictReader(io.StringIO(content))
        rows = list(reader)
        data["columns"] = reader.fieldnames if reader.fieldnames else []
        data["row_count"] = len(rows)
        data["phases_found"] = len(rows)
        
        # Extract numeric data
        total_area = 0
        total_pct = 0.0
        
        for row in rows:
            row_data = {"raw": str(row)}
            # Find Area (pixels)
            area = 0
            for k, v in row.items():
                if not v: continue
                val_str = str(v).strip()
                # Look for integer values that look like pixel counts (>100)
                # or columns named 'Area'
                if k and 'area' in k.lower() and 'pct' not in k.lower() and 'fract' not in k.lower():
                    try: 
                        val = float(re.findall(r"[\d\.]+", val_str)[0])
                        area = val
                    except: pass
                elif not k and val_str.isdigit() and int(val_str) > 100:
                     area = float(val_str)
            
            # Find Fraction (%)
            pct = 0.0
            for k, v in row.items():
                if not v: continue
                val_str = str(v).strip()
                if k and ('pct' in k.lower() or 'percent' in k.lower() or 'fraction' in k.lower()):
                    try:
                        val = float(re.findall(r"[\d\.]+", val_str)[0])
                        # Handle fraction vs percent (0.5 vs 50)
                        if val <= 1.0 and val > 0: val *= 100
                        pct = val
                    except: pass
            
            # Fallback parsing if headers are missing/weird: look for values in row
            if area == 0 or pct == 0:
                nums = [float(n) for n in re.findall(r"[\d\.]+", str(list(row.values())))]
                # Heuristic: Area is usually > 1000, Pct is < 100
                potential_areas = [n for n in nums if n > 1000]
                potential_pcts = [n for n in nums if 0 < n <= 100]
                if potential_areas and area == 0: area = potential_areas[0]
                if potential_pcts and pct == 0: pct = potential_pcts[0]

            row_data["area"] = area
            row_data["pct"] = pct
            data["numeric_data"].append(row_data)
            
            total_area += area
            total_pct += pct

        data["total_area_pixels"] = total_area
        data["total_fraction_pct"] = total_pct
        
        if len(rows) >= 3 and total_pct > 0:
            data["valid_format"] = True

    except Exception as e:
        print(f"Parsing error: {e}")

# Save JSON
with open(output_json, 'w') as f:
    json.dump(data, f, indent=2)

print(f"JSON Export complete. Exists: {data['file_exists']}, Rows: {data['row_count']}")
PYEOF

echo "=== Export Complete ==="