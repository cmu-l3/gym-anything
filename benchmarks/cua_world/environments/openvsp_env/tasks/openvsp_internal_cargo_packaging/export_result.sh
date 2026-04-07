#!/bin/bash
# Export script for openvsp_internal_cargo_packaging task
# Safely captures file metadata and contents into JSON for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_packaging_result.json"
MODEL_PATH="$MODELS_DIR/eCRM001_packaged.vsp3"

echo "=== Exporting result for openvsp_internal_cargo_packaging ==="

# Take final screenshot as evidence
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release any file locks
kill_openvsp

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Run python script to safely encode XML content into JSON
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
task_start = int('$TASK_START')

exists = os.path.isfile(model_path)
mtime = int(os.path.getmtime(model_path)) if exists else 0
size = os.path.getsize(model_path) if exists else 0
created_during_task = mtime >= task_start

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_size': size,
    'file_mtime': mtime,
    'task_start': task_start,
    'created_during_task': created_during_task,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported: exists={exists}, size={size}, valid_time={created_during_task}")
PYEOF

echo "=== Export complete ==="