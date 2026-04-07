#!/bin/bash
# Export script for openvsp_helicopter_rotor_layout task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_helicopter_result.json"
MODEL_PATH="$MODELS_DIR/helicopter_configured.vsp3"

echo "=== Exporting result for openvsp_helicopter_rotor_layout ==="

# Take final screenshot before closing
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to ensure the file is completely written and locks are released
kill_openvsp

# Extract data using Python to handle JSON safely
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
start_time_file = '/tmp/task_start_timestamp'

# Read task start time
try:
    with open(start_time_file, 'r') as f:
        task_start = int(f.read().strip())
except:
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
    'file_content': content,
    'mtime': mtime,
    'task_start': task_start,
    'file_created_during_task': mtime >= task_start if exists else False
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported Result: exists={exists}, size={size} bytes, created_during_task={result['file_created_during_task']}")
PYEOF

echo "=== Export complete ==="