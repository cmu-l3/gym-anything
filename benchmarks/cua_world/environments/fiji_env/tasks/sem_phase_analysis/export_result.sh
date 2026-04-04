#!/bin/bash
echo "=== Exporting SEM Phase Analysis Result ==="

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Define paths
CSV_PATH="/home/ga/Fiji_Data/results/sem_analysis/particle_measurements.csv"
OVERLAY_PATH="/home/ga/Fiji_Data/results/sem_analysis/segmentation_overlay.png"
SUMMARY_PATH="/home/ga/Fiji_Data/results/sem_analysis/phase_summary.txt"
JSON_OUTPUT="/tmp/sem_analysis_result.json"

# Use Python to parse results and verify content robustly
python3 << PYEOF
import json
import os
import csv
import re
import math

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": False,
    "csv_modified": False,
    "csv_valid": False,
    "csv_rows": 0,
    "csv_cols": [],
    "mean_area": 0,
    "calibration_check": "unknown",
    "overlay_exists": False,
    "overlay_modified": False,
    "overlay_size": 0,
    "summary_exists": False,
    "summary_modified": False,
    "summary_data": {},
    "app_running": False
}

# 1. Check CSV
if os.path.exists("$CSV_PATH"):
    result["csv_exists"] = True
    if os.path.getmtime("$CSV_PATH") > $TASK_START:
        result["csv_modified"] = True
    
    try:
        with open("$CSV_PATH", 'r') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                result["csv_cols"] = [c.lower() for c in reader.fieldnames]
                
                areas = []
                count = 0
                for row in reader:
                    count += 1
                    # Try to find area column
                    for k, v in row.items():
                        if "area" in k.lower():
                            try:
                                areas.append(float(v))
                            except:
                                pass
                
                result["csv_rows"] = count
                
                if areas:
                    avg_area = sum(areas) / len(areas)
                    result["mean_area"] = avg_area
                    
                    # Calibration heuristic: 
                    # If calibrated (microns), avg area should be ~20-50 um^2
                    # If uncalibrated (pixels), avg area would be ~20/(0.49*0.49) ~= 83 pixels
                    # Actually, raw pixels are roughly 100-2000 px range.
                    # Wait, 1 px = 0.49 um -> 1 px^2 = 0.24 um^2.
                    # If uncalibrated, values will be LARGER than calibrated values if > 1px.
                    # Wait. Area in px. Area in um^2 = Area_px * 0.49 * 0.49 = Area_px * 0.24.
                    # So calibrated values are SMALLER than pixel values.
                    # Mean particle area for this image is roughly 10-50 um^2.
                    # In pixels, that would be 40-200 pixels.
                    # So 10-50 vs 40-200 is close, but distinguishable if we look at max.
                    # Max particle in um^2 is ~300. In pixels ~1200.
                    # A better check is the magnitude.
                    
                    if avg_area > 0 and avg_area < 500:
                         result["calibration_check"] = "likely_calibrated"
                    elif avg_area > 500:
                         result["calibration_check"] = "likely_pixels"
                    
                result["csv_valid"] = True
    except Exception as e:
        result["csv_error"] = str(e)

# 2. Check Overlay
if os.path.exists("$OVERLAY_PATH"):
    result["overlay_exists"] = True
    result["overlay_size"] = os.path.getsize("$OVERLAY_PATH")
    if os.path.getmtime("$OVERLAY_PATH") > $TASK_START:
        result["overlay_modified"] = True

# 3. Check Summary Text
if os.path.exists("$SUMMARY_PATH"):
    result["summary_exists"] = True
    if os.path.getmtime("$SUMMARY_PATH") > $TASK_START:
        result["summary_modified"] = True
    
    try:
        with open("$SUMMARY_PATH", 'r') as f:
            text = f.read()
            # Try to extract key numbers using regex
            # Look for integers (count) and floats (area, fraction)
            
            # Simple keyword search
            data = {}
            
            # Count
            count_match = re.search(r'(count|particles?|number).{0,10}(\d+)', text, re.IGNORECASE)
            if count_match:
                data['count'] = int(count_match.group(2))
            
            # Area Fraction
            frac_match = re.search(r'(fraction|%).{0,10}(\d+\.?\d*)', text, re.IGNORECASE)
            if frac_match:
                data['area_fraction'] = float(frac_match.group(2))
                
            # Mean Area
            area_match = re.search(r'(mean area|avg area).{0,10}(\d+\.?\d*)', text, re.IGNORECASE)
            if area_match:
                data['mean_area'] = float(area_match.group(2))
            
            result["summary_data"] = data
    except Exception as e:
        result["summary_error"] = str(e)

# 4. Check App
# Use shell command output passed to python or just check pid
# Simple check logic in python is hard without psutil, so we trust the bash pgrep below
pass

with open("$JSON_OUTPUT", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Check if Fiji is running
if pgrep -f "fiji" >/dev/null || pgrep -f "ImageJ" >/dev/null; then
    # Use python to update the json
    python3 -c "import json; d=json.load(open('$JSON_OUTPUT')); d['app_running']=True; json.dump(d, open('$JSON_OUTPUT','w'))"
fi

echo "Results exported to $JSON_OUTPUT"
chmod 666 "$JSON_OUTPUT"
cat "$JSON_OUTPUT"