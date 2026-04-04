#!/bin/bash
echo "=== Exporting Noise Filter Evaluation Results ==="

# Record task end info
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
RESULT_DIR="/home/ga/Fiji_Data/results/filter_comparison"
RESULT_JSON="/tmp/filter_task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to analyze results and generate a JSON summary
python3 << PYEOF
import os
import json
import csv
import sys
import numpy as np

result_dir = "$RESULT_DIR"
task_start = int("$TASK_START")

output = {
    "files": {},
    "csv_data": [],
    "report_content": "",
    "csv_valid": False,
    "report_valid": False,
    "images_valid": False,
    "snr_improvement": False,
    "std_reduction": False,
    "task_start": task_start
}

required_files = [
    "gaussian_filtered.tif", 
    "median_filtered.tif", 
    "mean_filtered.tif", 
    "filter_comparison.csv", 
    "filter_report.txt"
]

# 1. Check file existence and modification times
for fname in required_files:
    fpath = os.path.join(result_dir, fname)
    if os.path.exists(fpath):
        mtime = int(os.path.getmtime(fpath))
        size = os.path.getsize(fpath)
        output["files"][fname] = {
            "exists": True,
            "modified_after_start": mtime > task_start,
            "size": size
        }
    else:
        output["files"][fname] = {"exists": False}

# 2. Parse CSV
csv_path = os.path.join(result_dir, "filter_comparison.csv")
if output["files"]["filter_comparison.csv"]["exists"]:
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            # Normalize headers
            if reader.fieldnames:
                reader.fieldnames = [h.lower().strip() for h in reader.fieldnames]
            
            rows = list(reader)
            output["csv_data"] = rows
            
            # Validation logic
            if len(rows) >= 4:
                # Check for required filters
                filters = [r.get('filter', '').lower() for r in rows]
                has_filters = all(f in filters for f in ['original', 'gaussian', 'median', 'mean'])
                
                # Check SNR calculation
                valid_snr = True
                snr_improved = 0
                std_reduced = 0
                
                orig_snr = 0
                orig_std = 0
                
                # Find original stats first
                for r in rows:
                    if r.get('filter', '').lower() == 'original':
                        try:
                            orig_snr = float(r.get('snr', 0))
                            orig_std = float(r.get('stddev', 0))
                        except: pass
                
                for r in rows:
                    try:
                        name = r.get('filter', '').lower()
                        snr = float(r.get('snr', 0))
                        std = float(r.get('stddev', 0))
                        
                        if name != 'original':
                            if snr > orig_snr: snr_improved += 1
                            if std < orig_std: std_reduced += 1
                    except:
                        valid_snr = False
                
                output["csv_valid"] = has_filters and valid_snr
                output["snr_improvement"] = (snr_improved >= 3) # All 3 filters should improve SNR
                output["std_reduction"] = (std_reduced >= 3)
            
    except Exception as e:
        print(f"Error parsing CSV: {e}")

# 3. Check Report
report_path = os.path.join(result_dir, "filter_report.txt")
if output["files"]["filter_report.txt"]["exists"]:
    try:
        with open(report_path, 'r') as f:
            content = f.read().lower()
            output["report_content"] = content
            # Check for keywords
            if "best" in content and any(f in content for f in ["gaussian", "median", "mean"]):
                output["report_valid"] = True
    except: pass

# 4. Write JSON
with open("$RESULT_JSON", "w") as f:
    json.dump(output, f, indent=2)

print("Export analysis complete.")
PYEOF

# Fix permissions
chown ga:ga "$RESULT_JSON"
chmod 666 "$RESULT_JSON"

echo "Result JSON saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="