#!/bin/bash
# Export script for Multi-Channel ROI Profiling

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Multi-Channel ROI Result ==="

# 1. Take final screenshot for VLM verification
take_screenshot /tmp/task_end_screenshot.png

# 2. Define paths
RESULT_FILE="/home/ga/ImageJ_Data/results/nuclei_stack_profiles.csv"
TASK_START_FILE="/tmp/task_start_timestamp"
EXPORT_JSON="/tmp/multichannel_roi_result.json"

# 3. Python script to parse the CSV and generate JSON summary
# We do parsing here to simplify the host verifier and avoid environment issues
python3 << 'PYEOF'
import json
import os
import csv
import sys
import re

result_path = "/home/ga/ImageJ_Data/results/nuclei_stack_profiles.csv"
start_time_path = "/tmp/task_start_timestamp"
output_json = "/tmp/multichannel_roi_result.json"

summary = {
    "file_exists": False,
    "file_created_during_task": False,
    "row_count": 0,
    "unique_rois": 0,
    "slices_measured": 0,
    "has_mean_column": False,
    "has_area_column": False,
    "channel_variance_detected": False,
    "nuclei_signature_detected": False,
    "error": None
}

try:
    # Check file existence and timestamp
    if os.path.exists(result_path):
        summary["file_exists"] = True
        mtime = os.path.getmtime(result_path)
        
        start_time = 0
        if os.path.exists(start_time_path):
            with open(start_time_path, 'r') as f:
                start_time = int(f.read().strip())
        
        if mtime > start_time:
            summary["file_created_during_task"] = True
            
        # Parse content
        with open(result_path, 'r', errors='replace') as f:
            content = f.read()
            
        # Determine if CSV or Tab-delimited (ImageJ often saves as XLS/Text)
        delimiter = ',' if ',' in content else '\t'
        lines = [l for l in content.split('\n') if l.strip()]
        
        if len(lines) > 1:
            reader = csv.DictReader(lines, delimiter=delimiter)
            rows = list(reader)
            summary["row_count"] = len(rows)
            
            if rows:
                fieldnames = [k.lower() for k in (reader.fieldnames or [])]
                summary["has_mean_column"] = any('mean' in k for k in fieldnames)
                summary["has_area_column"] = any('area' in k for k in fieldnames)
                
                # Analyze data structure
                # ImageJ Multi-Measure usually outputs: Label (ROI1:1, ROI1:2...), Slice, Mean...
                # OR if "One row per slice" is off: Label, Mean1, Mean2...
                
                slice_data = {} # {roi_id: {slice_num: mean_val}}
                
                for row in rows:
                    # Try to parse Label and Slice
                    # Common formats: "001:1", "001:2" or explicit Slice column
                    label = row.get('Label', '') or row.get('label', '') or row.get('', 'Unknown')
                    slice_num = 0
                    mean_val = 0.0
                    
                    # Try to get mean value
                    for k, v in row.items():
                        if 'mean' in k.lower():
                            try:
                                mean_val = float(v)
                            except: pass
                            break
                            
                    # Strategy 1: Explicit Slice column
                    if 'Slice' in row or 'slice' in row:
                        try:
                            slice_num = int(row.get('Slice') or row.get('slice'))
                            # ROI ID is the label without slice info
                            roi_id = label.split(':')[0]
                        except: pass
                        
                    # Strategy 2: Label contains slice info (e.g. "003-1:1")
                    elif ':' in label:
                        parts = label.rsplit(':', 1)
                        roi_id = parts[0]
                        if parts[1].isdigit():
                            slice_num = int(parts[1])
                            
                    if roi_id and slice_num > 0:
                        if roi_id not in slice_data:
                            slice_data[roi_id] = {}
                        slice_data[roi_id][slice_num] = mean_val

                summary["unique_rois"] = len(slice_data)
                
                # Check slice coverage
                all_slices = set()
                for r in slice_data.values():
                    all_slices.update(r.keys())
                summary["slices_measured"] = len(all_slices)
                
                # Check variance (Anti-gaming: are channels actually different?)
                # In this image: Slice 3 (Blue) is nuclei (high signal), Slice 1/2 are cytoplasm/other
                # So for a nucleus ROI, Slice 3 should be bright, others different
                variance_found = False
                nuclei_sig_found = False
                
                for roi, measures in slice_data.items():
                    vals = list(measures.values())
                    if len(vals) >= 2:
                        # Check if values are not identical
                        if max(vals) - min(vals) > 5: 
                            variance_found = True
                        
                        # Check if Slice 3 is significantly bright (simple heuristic)
                        # 8-bit image, nuclei are usually > 50 intensity
                        if 3 in measures and measures[3] > 30:
                            nuclei_sig_found = True
                            
                summary["channel_variance_detected"] = variance_found
                summary["nuclei_signature_detected"] = nuclei_sig_found

except Exception as e:
    summary["error"] = str(e)

with open(output_json, 'w') as f:
    json.dump(summary, f, indent=2)
PYEOF

echo "Result JSON generated at $EXPORT_JSON"
cat "$EXPORT_JSON"

echo "=== Export Complete ==="