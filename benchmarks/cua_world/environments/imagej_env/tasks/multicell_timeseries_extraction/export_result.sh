#!/bin/bash
# Export script for multicell_timeseries_extraction task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Time-Series Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Paths
RESULTS_DIR="/home/ga/ImageJ_Data/results"
CSV_FILE="$RESULTS_DIR/time_series_traces.csv"
ROI_FILE="$RESULTS_DIR/cell_rois.zip"
TASK_START_FILE="/tmp/task_start_timestamp"

# Create a python script to analyze the output files and create a summary JSON
# We do this here to package metadata for the verifier
python3 << 'PYEOF'
import json
import os
import csv
import zipfile
import sys
import time

results_path = "/home/ga/ImageJ_Data/results/time_series_traces.csv"
rois_path = "/home/ga/ImageJ_Data/results/cell_rois.zip"
task_start_path = "/tmp/task_start_timestamp"

output = {
    "csv_exists": False,
    "rois_exists": False,
    "csv_created_after_start": False,
    "rois_created_after_start": False,
    "row_count": 0,
    "col_count": 0,
    "roi_count": 0,
    "data_looks_numeric": False,
    "data_varies": False,
    "timestamp": time.time()
}

# Get task start time
try:
    with open(task_start_path, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# Check CSV
if os.path.exists(results_path):
    output["csv_exists"] = True
    mtime = os.path.getmtime(results_path)
    if mtime > task_start:
        output["csv_created_after_start"] = True
    
    try:
        with open(results_path, 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
            output["row_count"] = len(rows)
            if len(rows) > 0:
                output["col_count"] = len(rows[0])
                
                # Check for numeric data in a sample column (skip header)
                # Assuming standard ImageJ results where col 0 might be Label/Index
                # We check a few values to see if they change
                numeric_values = []
                for r in rows[1:]:
                    if len(r) > 1:
                        try:
                            # Try last column
                            val = float(r[-1])
                            numeric_values.append(val)
                        except:
                            pass
                
                if len(numeric_values) > 5:
                    output["data_looks_numeric"] = True
                    # Check variance
                    if max(numeric_values) - min(numeric_values) > 0:
                        output["data_varies"] = True

    except Exception as e:
        output["csv_error"] = str(e)

# Check ROIs
if os.path.exists(rois_path):
    output["rois_exists"] = True
    mtime = os.path.getmtime(rois_path)
    if mtime > task_start:
        output["rois_created_after_start"] = True
    
    try:
        with zipfile.ZipFile(rois_path, 'r') as z:
            # Count files ending in .roi
            rois = [n for n in z.namelist() if n.endswith('.roi')]
            output["roi_count"] = len(rois)
    except Exception as e:
        output["roi_error"] = str(e)

# Save summary
with open("/tmp/multicell_timeseries_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Export summary created.")
PYEOF

echo "=== Export Complete ==="