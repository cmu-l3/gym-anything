#!/bin/bash
# Export script for ROI Signal-to-Background Ratio task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting ROI SBR Task Results ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
CSV_PATH="/home/ga/ImageJ_Data/results/roi_measurements.csv"
ZIP_PATH="/home/ga/ImageJ_Data/results/roi_set.zip"
TIMESTAMP_FILE="/tmp/task_start_timestamp"

# Run Python parsing script
python3 << 'PYEOF'
import json
import csv
import os
import zipfile
import re
import sys

result = {
    "csv_exists": False,
    "zip_exists": False,
    "file_created_during_task": False,
    "row_count": 0,
    "roi_count": 0,
    "has_labels": False,
    "has_mean": False,
    "has_area": False,
    "label_compliance": False,
    "sbr_found": False,
    "sbr_value": 0.0,
    "signal_mean": 0.0,
    "bg_mean": 0.0,
    "sanity_check_passed": False,
    "errors": []
}

csv_path = "/home/ga/ImageJ_Data/results/roi_measurements.csv"
zip_path = "/home/ga/ImageJ_Data/results/roi_set.zip"
timestamp_path = "/tmp/task_start_timestamp"

try:
    # Check timestamps
    task_start = 0
    if os.path.exists(timestamp_path):
        with open(timestamp_path, 'r') as f:
            task_start = int(f.read().strip())

    # Verify CSV
    if os.path.exists(csv_path):
        result["csv_exists"] = True
        mtime = os.path.getmtime(csv_path)
        if mtime > task_start:
            result["file_created_during_task"] = True
        
        # Parse CSV content
        try:
            with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
                f.seek(0)
                reader = csv.DictReader(f)
                rows = list(reader)
                result["row_count"] = len(rows)
                
                if rows:
                    keys = [k.lower() for k in rows[0].keys()]
                    result["has_labels"] = any('label' in k or 'name' in k for k in keys)
                    result["has_mean"] = any('mean' in k for k in keys)
                    result["has_area"] = any('area' in k for k in keys)
                    
                    # Analyze ROI types and intensities
                    signal_means = []
                    bg_means = []
                    has_signal_label = False
                    has_bg_label = False
                    
                    for row in rows:
                        # Find label column (keys might vary like "Label", "Name", " ")
                        label_val = ""
                        for k, v in row.items():
                            if 'label' in k.lower() or 'name' in k.lower():
                                label_val = str(v).lower()
                        
                        # Fallback: if no named label col, check first column
                        if not label_val and list(row.values()):
                            label_val = str(list(row.values())[0]).lower()

                        # Extract Mean intensity
                        mean_val = 0.0
                        for k, v in row.items():
                            if 'mean' in k.lower():
                                try:
                                    mean_val = float(v)
                                except:
                                    pass
                        
                        # Categorize
                        if 'signal' in label_val or 'cell' in label_val:
                            has_signal_label = True
                            if mean_val > 0: signal_means.append(mean_val)
                        elif 'back' in label_val or 'bg' in label_val:
                            has_bg_label = True
                            if mean_val > 0: bg_means.append(mean_val)
                            
                    result["label_compliance"] = has_signal_label and has_bg_label
                    
                    # Calculate stats for sanity check
                    if signal_means and bg_means:
                        avg_sig = sum(signal_means) / len(signal_means)
                        avg_bg = sum(bg_means) / len(bg_means)
                        result["signal_mean"] = avg_sig
                        result["bg_mean"] = avg_bg
                        if avg_sig > avg_bg:
                            result["sanity_check_passed"] = True

                    # Search for SBR value in the file
                    # It might be a specific row, a column, or just text appended
                    sbr_pattern = re.compile(r'(sbr|ratio|signal.?to.?background)[\s:_\-,]*([0-9\.]+)', re.IGNORECASE)
                    
                    # Check text content for SBR pattern
                    match = sbr_pattern.search(content)
                    if match:
                        try:
                            result["sbr_value"] = float(match.group(2))
                            result["sbr_found"] = True
                        except:
                            pass
                    
                    # Also check if it's a column in the CSV
                    if not result["sbr_found"]:
                        for row in rows:
                            for k, v in row.items():
                                if 'sbr' in k.lower() or 'ratio' in k.lower():
                                    try:
                                        val = float(v)
                                        if val > 0:
                                            result["sbr_value"] = val
                                            result["sbr_found"] = True
                                    except:
                                        pass

        except Exception as e:
            result["errors"].append(f"CSV parse error: {str(e)}")

    # Verify ZIP
    if os.path.exists(zip_path):
        result["zip_exists"] = True
        try:
            with zipfile.ZipFile(zip_path, 'r') as z:
                rois = [n for n in z.namelist() if n.endswith('.roi')]
                result["roi_count"] = len(rois)
        except Exception as e:
            result["errors"].append(f"ZIP parse error: {str(e)}")

except Exception as e:
    result["errors"].append(f"Script error: {str(e)}")

with open("/tmp/roi_sbr_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON generated at /tmp/roi_sbr_result.json"
cat /tmp/roi_sbr_result.json
echo "=== Export Complete ==="