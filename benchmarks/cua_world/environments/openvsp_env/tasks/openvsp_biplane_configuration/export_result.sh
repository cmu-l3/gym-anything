#!/bin/bash
# Export script for openvsp_biplane_configuration task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_biplane_result.json"
MODEL_PATH="$MODELS_DIR/tiger_moth_biplane.vsp3"

echo "=== Exporting result for openvsp_biplane_configuration ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush file writes and release locks
kill_openvsp
sleep 1

# Export file metadata and content to JSON
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
start_time_file = '/tmp/task_start_timestamp'

# Read task start time
try:
    with open(start_time_file, 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'task_start': task_start,
    'file_created_during_task': (mtime >= task_start) if task_start > 0 else True,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result: file_exists={exists}, size={size}, created_during_task={result['file_created_during_task']}")
PYEOF

echo "=== Export complete ==="