#!/bin/bash
# Export script for openvsp_multi_section_sailplane task
# Copies sailplane_15m.vsp3 content for verification and checks timestamps

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_multi_section_sailplane_result.json"
MODEL_PATH="$MODELS_DIR/sailplane_15m.vsp3"

echo "=== Exporting result for openvsp_multi_section_sailplane ==="

# Take final screenshot before stopping OpenVSP
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP so file handles are released
kill_openvsp

# Extract data to JSON
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
task_start_file = '/tmp/task_start_timestamp'

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
content = ''
mtime = int(os.path.getmtime(model_path)) if exists else 0

try:
    with open(task_start_file, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_size': size,
    'file_content': content,
    'mtime': mtime,
    'task_start': task_start,
    'created_during_task': mtime > task_start if exists else False
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported Result: exists={exists}, size={size}, created_during_task={result['created_during_task']}")
PYEOF

echo "=== Export complete ==="