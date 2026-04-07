#!/bin/bash
set -euo pipefail

echo "=== Exporting friction_sensitivity_study Result ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Read start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_FILE="/home/ga/Documents/CoppeliaSim/exports/friction_sweep.csv"
JSON_FILE="/home/ga/Documents/CoppeliaSim/exports/friction_report.json"

# Use Python to safely parse and extract all required data
# This avoids bash quoting/parsing issues with CSVs and JSONs
python3 << EOF > /tmp/task_result.json
import os
import json
import csv

task_start = int("$TASK_START")
csv_path = "$CSV_FILE"
json_path = "$JSON_FILE"

res = {
    "task_start": task_start,
    "csv_exists": False,
    "csv_is_new": False,
    "csv_row_count": 0,
    "frictions": [],
    "distances": [],
    "has_fric_col": False,
    "has_dist_col": False,
    "json_exists": False,
    "json_is_new": False,
    "json_fields_valid": False,
    "total_trials": 0,
    "fric_min": 0.0,
    "fric_max": 0.0,
    "dist_min": 0.0,
    "dist_max": 0.0,
    "monotonic": False,
    "errors": []
}

# Check CSV
if os.path.exists(csv_path):
    res["csv_exists"] = True
    if os.path.getmtime(csv_path) > task_start:
        res["csv_is_new"] = True
    try:
        with open(csv_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        res["csv_row_count"] = len(rows)
        
        if len(rows) > 0 and rows[0]:
            # Flexible column matching
            headers = {k.strip().lower(): k for k in rows[0].keys() if k}
            
            fric_key = next((headers[k] for k in headers if 'fric' in k or 'coeff' in k or 'mu' in k), None)
            dist_key = next((headers[k] for k in headers if 'dist' in k or 'slide' in k), None)
            
            if fric_key: res["has_fric_col"] = True
            if dist_key: res["has_dist_col"] = True
            
            if fric_key and dist_key:
                for r in rows:
                    try:
                        f_val = float(r[fric_key])
                        d_val = float(r[dist_key])
                        res["frictions"].append(f_val)
                        res["distances"].append(d_val)
                    except ValueError:
                        pass
    except Exception as e:
        res["errors"].append(f"CSV parsing error: {str(e)}")

# Check JSON
if os.path.exists(json_path):
    res["json_exists"] = True
    if os.path.getmtime(json_path) > task_start:
        res["json_is_new"] = True
    try:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        
        req_fields = [
            "total_trials", "friction_min", "friction_max", 
            "max_slide_distance_m", "min_slide_distance_m", "monotonic_decreasing"
        ]
        if all(k in data for k in req_fields):
            res["json_fields_valid"] = True
            res["total_trials"] = int(data.get("total_trials", 0))
            res["fric_min"] = float(data.get("friction_min", 0.0))
            res["fric_max"] = float(data.get("friction_max", 0.0))
            res["dist_min"] = float(data.get("min_slide_distance_m", 0.0))
            res["dist_max"] = float(data.get("max_slide_distance_m", 0.0))
            res["monotonic"] = bool(data.get("monotonic_decreasing", False))
    except Exception as e:
        res["errors"].append(f"JSON parsing error: {str(e)}")

print(json.dumps(res, indent=2))
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result payload generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="