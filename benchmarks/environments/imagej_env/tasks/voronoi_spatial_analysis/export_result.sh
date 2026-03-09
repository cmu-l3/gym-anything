#!/bin/bash
# Export script for Voronoi Spatial Analysis task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Voronoi Analysis Result ==="

RESULT_FILE="/home/ga/ImageJ_Data/results/voronoi_spatial_analysis.csv"
OUTPUT_JSON="/tmp/task_result.json"
TASK_START_FILE="/tmp/task_start_timestamp"

# Capture final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to parse results and generate JSON
python3 << 'PYEOF'
import json
import os
import csv
import re
import sys

result_file = "/home/ga/ImageJ_Data/results/voronoi_spatial_analysis.csv"
task_start_file = "/tmp/task_start_timestamp"
output_json = "/tmp/task_result.json"

data = {
    "file_exists": False,
    "file_created_after_task": False,
    "row_count": 0,
    "area_values": [],
    "median_area": 0,
    "cv_found": False,
    "cv_value": None,
    "mean_found": False,
    "mean_value": None,
    "std_dev_found": False,
    "parse_error": None
}

# Check file existence and timestamp
try:
    if os.path.exists(result_file):
        data["file_exists"] = True
        file_mtime = os.path.getmtime(result_file)
        
        task_start = 0
        if os.path.exists(task_start_file):
            with open(task_start_file, 'r') as f:
                task_start = int(f.read().strip())
        
        data["file_created_after_task"] = file_mtime > task_start
        
        # Parse content
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        # Strategy 1: Look for summary statistics in text (often at bottom or top)
        # CV (Coefficient of Variation)
        cv_match = re.search(r'(?i)(cv|coefficient\s+of\s+variation|var.*?coeff).*?[:=,]\s*([\d\.]+)', content)
        if cv_match:
            try:
                data["cv_value"] = float(cv_match.group(2))
                data["cv_found"] = True
            except ValueError:
                pass
                
        # Mean
        mean_match = re.search(r'(?i)(mean|average).*?[:=,]\s*([\d\.]+)', content)
        if mean_match:
            try:
                data["mean_value"] = float(mean_match.group(2))
                data["mean_found"] = True
            except ValueError:
                pass

        # Strategy 2: Parse as CSV to get individual cell areas
        try:
            f_io = open(result_file, 'r', encoding='utf-8', errors='replace')
            reader = csv.reader(f_io)
            rows = list(reader)
            f_io.close()
            
            # Find Area column
            area_idx = -1
            header_row = -1
            
            for i, row in enumerate(rows):
                # Simple heuristic to find header
                for j, cell in enumerate(row):
                    if 'area' in cell.lower():
                        area_idx = j
                        header_row = i
                        break
                if area_idx != -1:
                    break
            
            # Extract areas
            areas = []
            if area_idx != -1:
                # Use identified column
                for i in range(header_row + 1, len(rows)):
                    if i < len(rows) and len(rows[i]) > area_idx:
                        try:
                            val = float(rows[i][area_idx])
                            if val > 0: areas.append(val)
                        except ValueError:
                            pass
            else:
                # Fallback: Look for any column with numeric values typical of areas
                # Blobs area ~200-5000
                possible_area_cols = []
                for j in range(len(rows[0]) if rows else 0):
                    col_vals = []
                    valid_cnt = 0
                    for i in range(1, len(rows)):
                        if j < len(rows[i]):
                            try:
                                val = float(rows[i][j])
                                col_vals.append(val)
                                if 10 < val < 10000: valid_cnt += 1
                            except ValueError:
                                pass
                    if len(col_vals) > 5 and valid_cnt / len(col_vals) > 0.8:
                        areas = col_vals # Assume this is it
                        break

            data["area_values"] = areas
            data["row_count"] = len(areas)
            
            if areas:
                areas.sort()
                data["median_area"] = areas[len(areas)//2]
                
                # Calculate stats if not found in text
                calc_mean = sum(areas) / len(areas)
                if not data["mean_found"]:
                    data["mean_value"] = calc_mean
                    data["mean_found"] = True
                    
                calc_std = (sum((x - calc_mean) ** 2 for x in areas) / len(areas)) ** 0.5
                calc_cv = calc_std / calc_mean if calc_mean > 0 else 0
                
                if not data["cv_found"]:
                    data["cv_value"] = calc_cv
                    data["cv_found"] = True

        except Exception as e:
            data["parse_error"] = str(e)

except Exception as e:
    data["parse_error"] = f"General error: {str(e)}"

with open(output_json, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

echo "Result JSON generated at $OUTPUT_JSON"
cat "$OUTPUT_JSON"
echo "=== Export complete ==="