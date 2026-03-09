#!/bin/bash
echo "=== Exporting PSF Measurement Results ==="

# 1. Capture Final State
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Paths
RESULTS_DIR="/home/ga/Fiji_Data/results/psf"
CSV_FILE="$RESULTS_DIR/fwhm_measurements.csv"
REPORT_FILE="$RESULTS_DIR/resolution_report.txt"
PLOT_FILE="$RESULTS_DIR/line_profile.png"
JSON_OUT="/tmp/psf_result.json"
TASK_START_FILE="/tmp/task_start_time"

# 3. Read Start Time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# 4. Analyze Results with Python
# We use an embedded python script to parse the CSV and report, checking timestamps
python3 << PY_EOF
import json
import os
import csv
import re
import sys

results = {
    "task_start": $TASK_START,
    "csv_exists": False,
    "csv_valid": False,
    "row_count": 0,
    "mean_fwhm_px": 0.0,
    "mean_fwhm_um": 0.0,
    "fwhm_cv": 0.0,
    "report_exists": False,
    "report_content": "",
    "plot_exists": False,
    "files_created_during_task": False
}

csv_path = "$CSV_FILE"
report_path = "$REPORT_FILE"
plot_path = "$PLOT_FILE"

# Check CSV
if os.path.exists(csv_path):
    results["csv_exists"] = True
    mtime = os.path.getmtime(csv_path)
    if mtime > results["task_start"]:
        results["files_created_during_task"] = True
    
    try:
        rows = []
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            # Normalize headers to lower case
            reader.fieldnames = [name.lower().strip() for name in reader.fieldnames] if reader.fieldnames else []
            for row in reader:
                rows.append(row)
        
        results["row_count"] = len(rows)
        
        # Calculate stats if columns exist
        fwhm_px_vals = []
        fwhm_um_vals = []
        
        for row in rows:
            # Try to find pixel column
            for key in row:
                if 'px' in key or 'pixel' in key:
                    try: fwhm_px_vals.append(float(row[key]))
                    except: pass
                if 'um' in key or 'micro' in key:
                    try: fwhm_um_vals.append(float(row[key]))
                    except: pass
        
        if fwhm_px_vals:
            mean = sum(fwhm_px_vals) / len(fwhm_px_vals)
            results["mean_fwhm_px"] = mean
            
            # Calculate Coefficient of Variation (CV) to check consistency
            if len(fwhm_px_vals) > 1:
                variance = sum((x - mean) ** 2 for x in fwhm_px_vals) / len(fwhm_px_vals)
                std_dev = variance ** 0.5
                results["fwhm_cv"] = std_dev / mean if mean > 0 else 0
            
            results["csv_valid"] = True

        if fwhm_um_vals:
             results["mean_fwhm_um"] = sum(fwhm_um_vals) / len(fwhm_um_vals)

    except Exception as e:
        results["csv_error"] = str(e)

# Check Report
if os.path.exists(report_path):
    results["report_exists"] = True
    try:
        with open(report_path, 'r') as f:
            content = f.read()
            results["report_content"] = content
            # Simple number extraction for verification
            numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
            results["report_numbers"] = numbers
    except:
        pass

# Check Plot
if os.path.exists(plot_path):
    results["plot_exists"] = True
    if os.path.getsize(plot_path) > 1024: # Must be > 1KB
        results["plot_valid_size"] = True

# Write JSON
with open("$JSON_OUT", 'w') as f:
    json.dump(results, f)

PY_EOF

# 5. Fix permissions so verifier (running as root/host) can definitely read it if needed
chmod 666 "$JSON_OUT"
echo "Results exported to $JSON_OUT"
cat "$JSON_OUT"