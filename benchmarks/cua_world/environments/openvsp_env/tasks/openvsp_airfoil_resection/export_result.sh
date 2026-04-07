#!/bin/bash
# Export script for openvsp_airfoil_resection task
# Records file metadata, diff from original, and captures content

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_airfoil_resection_result.json"
MODEL_PATH="$MODELS_DIR/eCRM001_resectioned.vsp3"

echo "=== Exporting result for openvsp_airfoil_resection ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush file to disk
kill_openvsp
sleep 1

# Get task start timestamp and original MD5
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
ORIGINAL_MD5=$(cat /tmp/original_md5.txt 2>/dev/null || echo "")

# Write result JSON using Python
python3 << PYEOF
import json
import os
import hashlib

model_path = '$MODEL_PATH'
task_start = int('$TASK_START')
original_md5 = '$ORIGINAL_MD5'

result = {
    'file_exists': False,
    'file_size': 0,
    'file_content': '',
    'created_during_task': False,
    'differs_from_original': False,
    'mtime': 0
}

if os.path.isfile(model_path):
    result['file_exists'] = True
    result['file_size'] = os.path.getsize(model_path)
    result['mtime'] = int(os.path.getmtime(model_path))
    result['created_during_task'] = result['mtime'] >= task_start
    
    with open(model_path, 'r', errors='replace') as f:
        result['file_content'] = f.read()
    
    with open(model_path, 'rb') as f:
        file_hash = hashlib.md5(f.read()).hexdigest()
        result['differs_from_original'] = (file_hash != original_md5)

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
print(f"Result written: file_exists={result['file_exists']}, differs={result['differs_from_original']}")
PYEOF

echo "=== Export complete ==="