#!/bin/bash
echo "=== Exporting export_model_with_patient_id result ==="

source /workspace/scripts/task_utils.sh

# Configuration
OUTPUT_DIR="/home/ga/Documents"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
SERIES_DIR="/home/ga/DICOM/ct_cranium"
IMPORT_DIR=$(pick_dicom_import_dir "$SERIES_DIR")

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Extract Ground Truth Patient ID again (to be robust)
GT_PATIENT_ID="unknown"
SAMPLE_DCM=$(find -L "$IMPORT_DIR" -type f \( -iname "*.dcm" -o -iname "*.dicom" -o -iname "*.ima" \) -print -quit)
if [ -n "$SAMPLE_DCM" ] && command -v dcmdump >/dev/null; then
    # Extract ID, remove whitespace/nulls
    GT_PATIENT_ID=$(dcmdump +P "0010,0020" "$SAMPLE_DCM" | sed -E 's/.*\[(.*)\].*/\1/' | tr -d '[:space:]\0')
fi

# 2. Analyze output files using Python
python3 << PYEOF
import os
import json
import glob
import re

output_dir = "$OUTPUT_DIR"
task_start = $TASK_START
ground_truth_id = "$GT_PATIENT_ID"

result = {
    "ground_truth_id": ground_truth_id,
    "files_found": [],
    "best_match": None,
    "success_candidate": False
}

# Find all STL files in documents
stl_files = glob.glob(os.path.join(output_dir, "*.stl"))

for filepath in stl_files:
    filename = os.path.basename(filepath)
    stats = os.stat(filepath)
    
    # Check if file is non-empty/valid size (>100KB)
    is_valid_size = stats.st_size > 102400
    
    # Check if created/modified after task start
    is_fresh = stats.st_mtime > task_start
    
    # Check if ID is in filename (case insensitive)
    # Allow ID to be separated by _ or just adjacent
    # Sanitize ID for regex (escape special chars)
    safe_id = re.escape(ground_truth_id)
    id_in_name = bool(re.search(safe_id, filename, re.IGNORECASE))
    
    # Check suffix
    has_suffix = filename.lower().endswith("_skull.stl")
    
    file_info = {
        "filename": filename,
        "path": filepath,
        "size_bytes": stats.st_size,
        "is_fresh": is_fresh,
        "contains_id": id_in_name,
        "has_correct_suffix": has_suffix,
        "is_valid_size": is_valid_size
    }
    
    result["files_found"].append(file_info)
    
    # Determine if this is a winning candidate
    if is_fresh and is_valid_size and id_in_name and has_suffix:
        result["success_candidate"] = True
        result["best_match"] = filename

# Write result
with open("/tmp/export_model_with_patient_id_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="