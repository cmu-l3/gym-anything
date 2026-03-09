#!/bin/bash
# Export result for manual_neck_crop_segmentation task

echo "=== Exporting manual_neck_crop_segmentation result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/cleaned_skull.nii.gz"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check file status using simple shell/python commands
# We do NOT do heavy NIfTI analysis here (no nibabel in container guaranteed)
# We just check existence, size, and timestamp. Verifier does the rest.

python3 << PYEOF
import os
import json
import time

output_path = "$OUTPUT_FILE"
task_start = $TASK_START
result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "created_during_task": False,
    "is_gzip": False,
    "filename": os.path.basename(output_path)
}

if os.path.isfile(output_path):
    result["file_exists"] = True
    stat = os.stat(output_path)
    result["file_size_bytes"] = stat.st_size
    
    # Check timestamp
    if stat.st_mtime > task_start:
        result["created_during_task"] = True
        
    # Check GZip magic bytes
    try:
        with open(output_path, "rb") as f:
            magic = f.read(2)
        if magic == b"\x1f\x8b":
            result["is_gzip"] = True
    except:
        pass

with open("/tmp/export_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="