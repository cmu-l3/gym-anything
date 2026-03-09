#!/bin/bash
echo "=== Exporting Particle Inclusion Analysis Results ==="

# Define paths
RESULTS_DIR="/home/ga/Fiji_Data/results/particles"
TASK_START_FILE="/tmp/task_start_time.txt"
EXPORT_JSON="/tmp/task_result.json"

# Read start time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to analyze results and generate JSON
python3 << EOF
import json
import os
import csv
import re
import sys

results_dir = "$RESULTS_DIR"
task_start = $TASK_START
output = {
    "files": {},
    "csv_data": {
        "valid_format": False,
        "row_count": 0,
        "columns_found": [],
        "calibrated": False,
        "mean_area": 0
    },
    "report_data": {
        "valid_format": False,
        "content": {}
    },
    "timestamp": task_start
}

# 1. Check Files Existence and Timestamps
expected_files = [
    "particle_measurements.csv",
    "size_distribution.png",
    "annotated_micrograph.png",
    "inclusion_report.txt"
]

for fname in expected_files:
    fpath = os.path.join(results_dir, fname)
    exists = os.path.exists(fpath)
    created_during_task = False
    size = 0
    
    if exists:
        mtime = os.path.getmtime(fpath)
        size = os.path.getsize(fpath)
        if mtime > task_start:
            created_during_task = True
            
    output["files"][fname] = {
        "exists": exists,
        "created_during_task": created_during_task,
        "size": size
    }

# 2. Analyze CSV Content
csv_path = os.path.join(results_dir, "particle_measurements.csv")
if output["files"]["particle_measurements.csv"]["exists"]:
    try:
        with open(csv_path, 'r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                # Normalize field names (strip spaces, lowercase)
                headers = [h.strip().lower() for h in reader.fieldnames]
                output["csv_data"]["columns_found"] = headers
                
                rows = list(reader)
                output["csv_data"]["row_count"] = len(rows)
                
                # Check for calibration by looking at Area values
                # Uncalibrated (pixels) area for particles is likely > 100
                # Calibrated (microns, 0.1725 scale) area ~ Area_px * 0.1725^2 = Area_px * 0.03
                # So 100 px area -> 3 um2. 
                # If values are typically < 1000, it's likely calibrated. If > 5000, likely pixels.
                
                areas = []
                area_col = next((h for h in reader.fieldnames if 'area' in h.lower()), None)
                
                if area_col:
                    valid_rows = 0
                    total_area = 0
                    for row in rows:
                        try:
                            val = float(row[area_col])
                            areas.append(val)
                            total_area += val
                            valid_rows += 1
                        except ValueError:
                            continue
                    
                    if valid_rows > 0:
                        mean_area = total_area / valid_rows
                        output["csv_data"]["mean_area"] = mean_area
                        # Heuristic: If mean area is between 1 and 1000, it's likely calibrated microns
                        # If mean area is > 2000, it's likely pixels (unless huge particles)
                        if 1.0 < mean_area < 2000.0:
                            output["csv_data"]["calibrated"] = True
                        
                output["csv_data"]["valid_format"] = True
    except Exception as e:
        print(f"Error parsing CSV: {e}")

# 3. Analyze Report Content
report_path = os.path.join(results_dir, "inclusion_report.txt")
if output["files"]["inclusion_report.txt"]["exists"]:
    try:
        with open(report_path, 'r') as f:
            content = f.read()
            
        # Parse key-value pairs
        # Looks for patterns like "key: value" or "key = value"
        data = {}
        
        patterns = {
            "total_particles": r"total_particles[:=\s]+(\d+)",
            "mean_area": r"mean_area[:=\s]+([\d\.]+)",
            "qc_result": r"qc_result[:=\s]+(PASS|FAIL)"
        }
        
        for key, pattern in patterns.items():
            match = re.search(pattern, content, re.IGNORECASE)
            if match:
                data[key] = match.group(1)
        
        output["report_data"]["content"] = data
        output["report_data"]["valid_format"] = True
        
    except Exception as e:
        print(f"Error parsing report: {e}")

# Write result
with open("$EXPORT_JSON", "w") as f:
    json.dump(output, f, indent=2)

EOF

# Ensure the JSON is readable
chmod 644 "$EXPORT_JSON" 2>/dev/null || true

echo "Export complete. Result saved to $EXPORT_JSON"
cat "$EXPORT_JSON"