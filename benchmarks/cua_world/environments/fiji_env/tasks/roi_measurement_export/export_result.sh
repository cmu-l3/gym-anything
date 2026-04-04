#!/bin/bash
echo "=== Exporting ROI Measurement Results ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Fiji_Data/results/roi_analysis"

# 2. Analyze results using Python script inside container
# We do this here to package the analysis into a JSON for the verifier
# This avoids dependency issues on the host side
python3 << 'EOF'
import os
import json
import csv
import zipfile
import time
import glob

results_dir = "/home/ga/Fiji_Data/results/roi_analysis"
task_start = 0
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    pass

output = {
    "csv_exists": False,
    "csv_valid": False,
    "csv_rows": 0,
    "csv_cols": [],
    "area_values": [],
    "zip_exists": False,
    "zip_valid": False,
    "roi_count": 0,
    "roi_types": [],
    "png_exists": False,
    "png_size": 0,
    "report_exists": False,
    "report_content": "",
    "timestamps_valid": True
}

# Check CSV
csv_path = os.path.join(results_dir, "roi_measurements.csv")
if os.path.exists(csv_path):
    output["csv_exists"] = True
    if os.path.getmtime(csv_path) < task_start:
        output["timestamps_valid"] = False
    
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            output["csv_rows"] = len(rows)
            if reader.fieldnames:
                output["csv_cols"] = reader.fieldnames
            
            # Extract area values to check calibration
            # Usually column is "Area"
            for row in rows:
                for k, v in row.items():
                    if k and "Area" in k:
                        try:
                            output["area_values"].append(float(v))
                        except:
                            pass
                        break
        output["csv_valid"] = True
    except Exception as e:
        print(f"CSV Error: {e}")

# Check ZIP
zip_path = os.path.join(results_dir, "roi_set.zip")
if os.path.exists(zip_path):
    output["zip_exists"] = True
    if os.path.getmtime(zip_path) < task_start:
        output["timestamps_valid"] = False
        
    try:
        with zipfile.ZipFile(zip_path, 'r') as z:
            names = z.namelist()
            rois = [n for n in names if n.lower().endswith('.roi')]
            output["roi_count"] = len(rois)
            
            # Basic type checking by reading first few bytes of ROI files if possible
            # ROI format: byte 6-7 is type code. 
            # 1=Rect, 2=Oval, 3=Polygon, 4=Freehand, 7=Freehand line...
            # This is complex to parse fully, so we might skip detailed type check here
            # and rely on count/names.
        output["zip_valid"] = True
    except Exception as e:
        print(f"ZIP Error: {e}")

# Check PNG
png_path = os.path.join(results_dir, "annotated_overlay.png")
if os.path.exists(png_path):
    output["png_exists"] = True
    output["png_size"] = os.path.getsize(png_path)
    if os.path.getmtime(png_path) < task_start:
        output["timestamps_valid"] = False

# Check Report
report_path = os.path.join(results_dir, "summary_report.txt")
if os.path.exists(report_path):
    output["report_exists"] = True
    if os.path.getmtime(report_path) < task_start:
        output["timestamps_valid"] = False
    try:
        with open(report_path, 'r') as f:
            output["report_content"] = f.read()
    except:
        pass

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f)
EOF

echo "Results exported to /tmp/task_result.json"