#!/bin/bash
# Export script for Shape-Based ROI Filtering task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Shape-Based ROI Filtering Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Paths
ROI_FILE="/home/ga/ImageJ_Data/results/circular_rois.zip"
CSV_FILE="/home/ga/ImageJ_Data/results/filtered_measurements.csv"
TIMESTAMP_FILE="/tmp/task_start_timestamp"

# Use Python to analyze results in the container
python3 << 'PYEOF'
import json
import csv
import os
import zipfile
import sys

roi_path = "/home/ga/ImageJ_Data/results/circular_rois.zip"
csv_path = "/home/ga/ImageJ_Data/results/filtered_measurements.csv"
timestamp_path = "/tmp/task_start_timestamp"

result = {
    "roi_file_exists": False,
    "csv_file_exists": False,
    "files_created_during_task": False,
    "roi_count_in_zip": 0,
    "csv_row_count": 0,
    "has_circularity_column": False,
    "min_circularity": 0.0,
    "max_circularity": 0.0,
    "csv_circularity_values": [],
    "valid_filter": False,
    "errors": []
}

try:
    # Check timestamps
    start_time = 0
    if os.path.exists(timestamp_path):
        with open(timestamp_path, 'r') as f:
            start_time = int(f.read().strip())
    
    # Check ROI Zip
    if os.path.exists(roi_path):
        mtime = os.path.getmtime(roi_path)
        if mtime > start_time:
            result["roi_file_exists"] = True
            try:
                with zipfile.ZipFile(roi_path, 'r') as zf:
                    # Count files ending in .roi
                    rois = [f for f in zf.namelist() if f.lower().endswith('.roi')]
                    result["roi_count_in_zip"] = len(rois)
            except Exception as e:
                result["errors"].append(f"Zip read error: {str(e)}")

    # Check CSV
    if os.path.exists(csv_path):
        mtime = os.path.getmtime(csv_path)
        if mtime > start_time:
            result["csv_file_exists"] = True
            try:
                with open(csv_path, 'r') as f:
                    # Sniff format or just read
                    content = f.read()
                    f.seek(0)
                    
                    # specific check for circularity headers
                    header_line = content.split('\n')[0].lower()
                    if 'circ' in header_line:
                        result["has_circularity_column"] = True
                    
                    # Parse values
                    reader = csv.DictReader(f) # Re-read using DictReader if headers exist
                    if not reader.fieldnames:
                        # Fallback for simple csv without proper headers or empty
                        f.seek(0)
                        reader = csv.reader(f)
                        rows = list(reader)
                        # Try to find circularity column index
                        circ_idx = -1
                        if rows:
                            headers = [h.lower() for h in rows[0]]
                            for i, h in enumerate(headers):
                                if 'circ' in h:
                                    circ_idx = i
                                    break
                            
                            # Extract data
                            if circ_idx != -1:
                                for row in rows[1:]:
                                    if len(row) > circ_idx:
                                        try:
                                            val = float(row[circ_idx])
                                            result["csv_circularity_values"].append(val)
                                        except:
                                            pass
                    else:
                        # DictReader path
                        for row in reader:
                            # find key for circularity
                            for k, v in row.items():
                                if k and 'circ' in k.lower():
                                    try:
                                        val = float(v)
                                        result["csv_circularity_values"].append(val)
                                    except:
                                        pass
                                    break # assume one circ column
            except Exception as e:
                result["errors"].append(f"CSV read error: {str(e)}")

    # Analyze Data
    vals = result["csv_circularity_values"]
    if vals:
        result["min_circularity"] = min(vals)
        result["max_circularity"] = max(vals)
        result["csv_row_count"] = len(vals)
        
        # Check if filter logic seems correct (allow small tolerance)
        if result["min_circularity"] >= 0.84:
            result["valid_filter"] = True
    
    # Global timestamp check
    if result["roi_file_exists"] and result["csv_file_exists"]:
        result["files_created_during_task"] = True

except Exception as e:
    result["errors"].append(f"Global error: {str(e)}")

# Save result
with open("/tmp/shape_roi_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

echo "=== Export Complete ==="