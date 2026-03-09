#!/bin/bash
echo "=== Exporting Cell Spacing Results ==="

# Paths
RESULTS_DIR="/home/ga/Fiji_Data/results/spacing"
CSV_FILE="$RESULTS_DIR/cell_measurements.csv"
MAP_FILE="$RESULTS_DIR/distance_map.tif"
REPORT_FILE="$RESULTS_DIR/spacing_report.txt"
QC_FILE="$RESULTS_DIR/qc_overlay.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to analyze results and generate JSON
python3 <<EOF
import os
import json
import csv
import re

results = {
    "task_start_time": $TASK_START,
    "csv_exists": False,
    "csv_valid": False,
    "csv_rows": 0,
    "csv_cols": [],
    "map_exists": False,
    "map_size_mb": 0,
    "report_exists": False,
    "report_data": {},
    "qc_exists": False,
    "files_newly_created": True
}

# Helper to check if file is newer than start time
def is_new(path):
    try:
        return os.path.getmtime(path) > $TASK_START
    except:
        return False

# --- Analyze CSV ---
csv_path = "$CSV_FILE"
if os.path.exists(csv_path):
    results["csv_exists"] = True
    if not is_new(csv_path): results["files_newly_created"] = False
    
    try:
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            headers = next(reader, [])
            rows = list(reader)
            
            results["csv_cols"] = [h.strip().lower() for h in headers]
            results["csv_rows"] = len(rows)
            
            # Basic validation: check for numeric data in a few rows
            if len(rows) > 0 and len(rows[0]) > 1:
                results["csv_valid"] = True
    except Exception as e:
        print(f"Error parsing CSV: {e}")

# --- Analyze Distance Map ---
map_path = "$MAP_FILE"
if os.path.exists(map_path):
    results["map_exists"] = True
    if not is_new(map_path): results["files_newly_created"] = False
    results["map_size_mb"] = os.path.getsize(map_path) / (1024 * 1024)

# --- Analyze Report ---
report_path = "$REPORT_FILE"
if os.path.exists(report_path):
    results["report_exists"] = True
    if not is_new(report_path): results["files_newly_created"] = False
    
    try:
        with open(report_path, 'r') as f:
            for line in f:
                if ':' in line or '=' in line:
                    sep = ':' if ':' in line else '='
                    key, val = line.split(sep, 1)
                    key = key.strip().lower()
                    val = val.strip()
                    # Try to convert to number
                    try:
                        if '.' in val: val = float(val)
                        else: val = int(val)
                    except:
                        pass
                    results["report_data"][key] = val
    except Exception as e:
        print(f"Error parsing report: {e}")

# --- Analyze QC Overlay ---
qc_path = "$QC_FILE"
if os.path.exists(qc_path):
    results["qc_exists"] = True
    if not is_new(qc_path): results["files_newly_created"] = False

# --- Save Result JSON ---
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)

print("Export logic complete.")
EOF

# 3. Move result to safe location and set permissions
mv /tmp/task_result.json /tmp/task_result_final.json 2>/dev/null || true
chmod 644 /tmp/task_result_final.json 2>/dev/null || true
echo "Result JSON saved to /tmp/task_result_final.json"
cat /tmp/task_result_final.json