#!/bin/bash
# Export script for MRI SNR/CNR Assessment task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting MRI SNR/CNR Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Python script to parse the CSV result file robustly
python3 << 'PYEOF'
import json
import csv
import os
import io
import re
import sys

# Configuration
result_file = "/home/ga/ImageJ_Data/results/mri_snr_cnr.csv"
task_start_file = "/tmp/task_start_timestamp"
output_json = "/tmp/mri_snr_cnr_assessment_result.json"

output = {
    "file_exists": False,
    "file_created_during_task": False,
    "row_count": 0,
    "regions_found": [],
    "measurements": {},
    "metrics_found": [],
    "values_consistency": True,  # Placeholder for calculation checks
    "parse_error": None
}

# Check file timestamps
try:
    with open(task_start_file, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

if os.path.isfile(result_file):
    output["file_exists"] = True
    mtime = int(os.path.getmtime(result_file))
    if mtime >= task_start:
        output["file_created_during_task"] = True
    
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        # Normalize content for parsing
        content_lower = content.lower()
        
        # Simple keyword search first
        regions = []
        if any(x in content_lower for x in ['white', 'wm', 'corpus']): regions.append('WM')
        if any(x in content_lower for x in ['gray', 'grey', 'gm', 'cortex']): regions.append('GM')
        if any(x in content_lower for x in ['back', 'bg', 'air']): regions.append('BG')
        output["regions_found"] = regions
        
        metrics = []
        if 'snr' in content_lower: metrics.append('SNR')
        if 'cnr' in content_lower: metrics.append('CNR')
        output["metrics_found"] = metrics

        # Attempt structured parsing to extract numbers
        # This handles both wide (Column=Metric) and tall (Row=Metric) formats
        # We look for numeric values associated with region keys
        
        # Helper to extract number from string
        def extract_float(s):
            try:
                # Find the first float-like pattern
                m = re.search(r"[-+]?\d*\.\d+|\d+", str(s))
                return float(m.group()) if m else None
            except:
                return None

        # Try parsing as CSV
        data_rows = []
        try:
            reader = csv.reader(io.StringIO(content))
            for row in reader:
                if any(cell.strip() for cell in row):
                    data_rows.append(row)
            output["row_count"] = len(data_rows)
        except:
            pass

        # Robust extraction strategy: look for patterns line by line if CSV structure is messy
        # We want to find: Mean_WM, Std_BG, Mean_GM
        
        extracted_values = {}
        
        # Define regex patterns for critical values
        # Looking for lines like "White Matter, 180.5, 5.2" or "Mean_WM, 180.5"
        
        lines = content.split('\n')
        for line in lines:
            line_lower = line.lower()
            vals = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", line)]
            if not vals: continue
            
            # Identify what this line might represent
            is_wm = any(x in line_lower for x in ['white', 'wm', 'corpus'])
            is_gm = any(x in line_lower for x in ['gray', 'grey', 'gm', 'cortex'])
            is_bg = any(x in line_lower for x in ['back', 'bg', 'air'])
            
            is_mean = any(x in line_lower for x in ['mean', 'avg'])
            is_std = any(x in line_lower for x in ['std', 'dev', 'sigma'])
            is_snr = 'snr' in line_lower
            is_cnr = 'cnr' in line_lower

            # Store found values
            # Heuristic: If line has "White Matter" and multiple numbers, usually [Area, Mean, Std, ...]
            # or [Mean, Std]. We assume Mean is larger than Std.
            
            val_mean = None
            val_std = None
            
            if len(vals) >= 2:
                # Assuming format like Label, Mean, Std or similar
                # Usually Mean >> Std in MRI
                sorted_vals = sorted(vals, reverse=True)
                val_mean = sorted_vals[0] # Largest is likely Mean (or Area, but Area usually > 255 for ROIs, Mean < 255 for 8bit)
                val_std = sorted_vals[-1] # Smallest is likely Std
                
                # Refinement for 8-bit image: Mean is 0-255. Area might be huge.
                # If largest value > 255, ignore it as Mean.
                candidates = [v for v in vals if v <= 255]
                if candidates:
                    val_mean = max(candidates)
                    if len(candidates) > 1:
                        val_std = min(candidates)
            elif len(vals) == 1:
                if is_mean: val_mean = vals[0]
                if is_std: val_std = vals[0]
                if is_snr: val_mean = vals[0] # Reuse val_mean slot for the metric value
                if is_cnr: val_mean = vals[0]

            # Assign to dictionary
            if is_wm:
                if val_mean is not None and not is_snr and not is_cnr: extracted_values['mean_wm'] = val_mean
                if val_std is not None: extracted_values['std_wm'] = val_std
                if is_snr and len(vals) > 0: extracted_values['snr_wm'] = vals[0]
            
            if is_gm:
                if val_mean is not None and not is_snr and not is_cnr: extracted_values['mean_gm'] = val_mean
                if val_std is not None: extracted_values['std_gm'] = val_std
                if is_snr and len(vals) > 0: extracted_values['snr_gm'] = vals[0]

            if is_bg:
                if val_mean is not None: extracted_values['mean_bg'] = val_mean
                if val_std is not None: extracted_values['std_bg'] = val_std
            
            if is_cnr and len(vals) > 0:
                extracted_values['cnr'] = vals[0]

        output["measurements"] = extracted_values

    except Exception as e:
        output["parse_error"] = str(e)

# Save JSON
with open(output_json, 'w') as f:
    json.dump(output, f, indent=2)

print(f"Parsed results: {json.dumps(output['measurements'])}")
PYEOF

echo "=== Export Complete ==="