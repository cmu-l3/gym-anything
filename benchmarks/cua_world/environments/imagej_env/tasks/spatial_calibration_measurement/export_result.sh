#!/bin/bash
# Export script for spatial_calibration_measurement task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Spatial Calibration Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Path to expected result file
RESULT_FILE="/home/ga/ImageJ_Data/results/calibrated_blob_measurements.csv"
TIMESTAMP_FILE="/tmp/task_start_timestamp"

# Use Python to parse the CSV and check for calibration indicators
# We do this here to package a clean JSON for the verifier
python3 << 'PYEOF'
import json
import csv
import os
import sys
import statistics

result_path = "/home/ga/ImageJ_Data/results/calibrated_blob_measurements.csv"
timestamp_path = "/tmp/task_start_timestamp"
output_path = "/tmp/spatial_calibration_result.json"

data = {
    "file_exists": False,
    "file_created_during_task": False,
    "row_count": 0,
    "columns": [],
    "median_area": 0,
    "median_feret": 0,
    "has_min_feret": False,
    "geometric_consistency": 0.0,  # Percentage of rows passing consistency check
    "error": None
}

try:
    # Check timestamp
    task_start = 0
    if os.path.exists(timestamp_path):
        with open(timestamp_path, 'r') as f:
            task_start = int(f.read().strip())

    if os.path.exists(result_path):
        data["file_exists"] = True
        mtime = os.path.getmtime(result_path)
        if mtime > task_start:
            data["file_created_during_task"] = True
        
        # Parse CSV
        rows = []
        with open(result_path, 'r', errors='replace') as f:
            # Handle potential different delimiters or file formats output by Fiji
            # Fiji 'Save As' often creates tab-delimited or csv depending on extension
            # We'll try standard CSV sniffer or fallback
            content = f.read()
            f.seek(0)
            
            try:
                dialect = csv.Sniffer().sniff(content[:1024])
                reader = csv.DictReader(f, dialect=dialect)
            except:
                # Fallback to assuming CSV or Tab
                f.seek(0)
                if '\t' in content.splitlines()[0]:
                    reader = csv.DictReader(f, delimiter='\t')
                else:
                    reader = csv.DictReader(f)
            
            data["columns"] = reader.fieldnames if reader.fieldnames else []
            
            areas = []
            ferets = []
            min_ferets = []
            consistent_count = 0
            
            for row in reader:
                rows.append(row)
                
                # Extract numerical values safely
                try:
                    # Look for Area column (case insensitive)
                    area_val = None
                    for k, v in row.items():
                        if k and 'area' in k.lower():
                            area_val = float(v)
                            break
                    
                    # Look for Feret column
                    feret_val = None
                    for k, v in row.items():
                        if k and k.lower() == 'feret': # Exact match preferred for Feret
                            feret_val = float(v)
                            break
                        elif k and 'feret' in k.lower() and 'min' not in k.lower() and 'angle' not in k.lower() and 'x' not in k.lower() and 'y' not in k.lower():
                             feret_val = float(v)
                    
                    # Look for MinFeret
                    min_feret_val = None
                    for k, v in row.items():
                        if k and 'min' in k.lower() and 'feret' in k.lower():
                            min_feret_val = float(v)
                            break
                    
                    if area_val is not None:
                        areas.append(area_val)
                    if feret_val is not None:
                        ferets.append(feret_val)
                    if min_feret_val is not None:
                        min_ferets.append(min_feret_val)
                    
                    # Geometric Consistency Check
                    # For a blob, Area approx equals Circle area with diam=Feret?
                    # Or at least Area < Feret^2
                    if area_val is not None and feret_val is not None and feret_val > 0:
                        # Circle area = pi * (d/2)^2 = 0.785 * d^2
                        # Square area = d^2
                        # Blob should be somewhere reasonable. 
                        # Ratio Area / Feret^2. Circle: 0.785. Square: 1.0. Thin line: ~0.
                        # If user typed random numbers, this ratio might be wild.
                        # Real blobs usually 0.3 to 0.9 range.
                        ratio = area_val / (feret_val * feret_val)
                        if 0.1 < ratio < 1.2:
                            consistent_count += 1
                            
                except ValueError:
                    continue

            data["row_count"] = len(rows)
            
            if areas:
                data["median_area"] = statistics.median(areas)
            if ferets:
                data["median_feret"] = statistics.median(ferets)
            
            data["has_min_feret"] = (len(min_ferets) > 0)
            
            if len(areas) > 0 and len(ferets) > 0:
                # Calculate consistency percentage based on smaller of the two counts
                count = min(len(areas), len(ferets))
                data["geometric_consistency"] = consistent_count / count

except Exception as e:
    data["error"] = str(e)

with open(output_path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

echo "Result JSON generated at /tmp/spatial_calibration_result.json"
cat /tmp/spatial_calibration_result.json