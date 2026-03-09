#!/bin/bash
echo "=== Exporting MRI Volume Estimation results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

RESULT_FILE="/home/ga/ImageJ_Data/results/mri_volume_results.csv"
OUTPUT_JSON="/tmp/mri_volume_estimation_result.json"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Check if result file exists, if not look for alternatives
if [ ! -f "$RESULT_FILE" ]; then
    echo "Result file not found at expected location."
    for alt in \
        "/home/ga/ImageJ_Data/results/"*.csv \
        "/home/ga/mri_volume_results.csv" \
        "/home/ga/Desktop/mri_volume_results.csv" \
        "/tmp/Results.csv" \
        "/home/ga/ImageJ_Data/measurements/"*.csv; do
        if [ -f "$alt" ]; then
            echo "Found alternative file: $alt"
            cp "$alt" "$RESULT_FILE"
            break
        fi
    done
fi

# Parse the CSV with Python
python3 << PYEOF
import json
import csv
import re
import statistics
import os
import sys

result = {
    "file_exists": False,
    "file_created_after_start": False,
    "file_size_bytes": 0,
    "total_data_rows": 0,
    "slice_numbers": [],
    "area_values": [],
    "area_std_dev": 0.0,
    "area_max": 0.0,
    "area_min_nonzero": 999999.0,
    "areas_above_5000": 0,
    "areas_below_5000": 0,
    "has_volume_total": False,
    "volume_total_value": 0.0,
    "slice_range_span": 0,
    "columns_found": [],
    "parse_error": None
}

result_file = "$RESULT_FILE"
task_start = $TASK_START

try:
    if os.path.exists(result_file):
        result["file_exists"] = True
        result["file_size_bytes"] = os.path.getsize(result_file)
        result["file_created_after_start"] = os.path.getmtime(result_file) > task_start

        with open(result_file, "r", errors="replace") as f:
            content = f.read()

        # 1. Search for total volume in raw text (comments or summary lines)
        # Look for patterns like "Total Volume: 12345" or "Sum: 12345"
        vol_patterns = [
            r'[Tt]otal[_ ]*[Vv]olume[^0-9]*([\d\.]+)',
            r'[Vv]olume[^0-9]*([\d\.]+)',
            r'[Ss]um[^0-9]*([\d\.]+)',
            r'Total[^0-9]*([\d\.]+)'
        ]
        
        for pat in vol_patterns:
            m = re.search(pat, content)
            if m:
                try:
                    val = float(m.group(1))
                    # Filter out small numbers that might be slice counts or indices
                    if val > 10000:
                        result["has_volume_total"] = True
                        result["volume_total_value"] = val
                        break
                except ValueError:
                    pass

        # 2. Parse CSV Data
        lines = content.strip().split('\n')
        
        # Filter valid data lines (skip comments)
        data_lines = [l for l in lines if l.strip() and not l.strip().startswith('#')]
        
        if data_lines:
            # Try to identify header
            header = data_lines[0].lower()
            if 'area' in header or 'label' in header or 'slice' in header:
                # likely a header
                keys = [k.strip() for k in header.split(',')]
                result["columns_found"] = keys
                # Determine indices
                area_idx = -1
                slice_idx = -1
                
                for i, k in enumerate(keys):
                    if 'area' in k: area_idx = i
                    if 'label' in k or 'slice' in k or 'num' in k: slice_idx = i
                
                # If area not found by name, assume 2nd column if numeric
                if area_idx == -1 and len(keys) >= 2:
                    # check 2nd line
                    if len(data_lines) > 1:
                        parts = data_lines[1].split(',')
                        if len(parts) >= 2 and parts[1].strip().replace('.','',1).isdigit():
                            area_idx = 1

                rows_start = 1
            else:
                # No header, assume raw data. usually index, area, ...
                rows_start = 0
                area_idx = 1 # guess
                slice_idx = 0 # guess

            # Process rows
            areas = []
            slices = []
            
            for line in data_lines[rows_start:]:
                parts = [p.strip() for p in line.split(',')]
                if not parts: continue
                
                # Check if this is a summary row
                if "total" in parts[0].lower() or "mean" in parts[0].lower():
                    # Check for volume in this row
                    for p in parts:
                        try:
                            val = float(p)
                            if val > 50000: # Heuristic for volume vs other stats
                                result["has_volume_total"] = True
                                result["volume_total_value"] = val
                        except ValueError:
                            pass
                    continue

                # Extract Area
                try:
                    val = 0.0
                    if area_idx != -1 and area_idx < len(parts):
                        val = float(parts[area_idx])
                    elif len(parts) >= 2:
                        # Try to find the largest number in the row that looks like area
                        nums = []
                        for p in parts:
                            try: nums.append(float(p))
                            except: pass
                        if nums: val = max(nums) # Areas are usually the largest numbers in these tables
                    
                    if val >= 0:
                        areas.append(val)
                except ValueError:
                    continue

                # Extract Slice ID
                try:
                    sl = 0
                    if slice_idx != -1 and slice_idx < len(parts):
                        # Handle "t1-head:10" format
                        txt = parts[slice_idx]
                        m = re.search(r'(\d+)', txt)
                        if m: sl = int(m.group(1))
                    else:
                        # Auto-increment if not found
                        sl = len(areas)
                    slices.append(sl)
                except ValueError:
                    pass

            result["total_data_rows"] = len(areas)
            result["area_values"] = areas
            result["slice_numbers"] = slices
            
            if areas:
                result["area_max"] = max(areas)
                result["area_std_dev"] = statistics.stdev(areas) if len(areas) > 1 else 0
                result["areas_above_5000"] = sum(1 for a in areas if a > 5000)
                result["areas_below_5000"] = sum(1 for a in areas if a <= 5000)
                
                nonzero = [a for a in areas if a > 0]
                if nonzero:
                    result["area_min_nonzero"] = min(nonzero)

            if slices:
                result["slice_range_span"] = max(slices) - min(slices) if len(slices) > 0 else 0

            # Backup volume check: Sum of areas
            if not result["has_volume_total"] and areas:
                total_area = sum(areas)
                if total_area > 10000:
                    result["has_volume_total"] = True
                    result["volume_total_value"] = total_area

except Exception as e:
    result["parse_error"] = str(e)

with open("$OUTPUT_JSON", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Results exported to $OUTPUT_JSON"
cat "$OUTPUT_JSON"