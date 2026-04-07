#!/bin/bash
# Export script for openvsp_propeller_blade_design task
set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_propeller_result.json"
MODEL_PATH="/home/ga/Documents/OpenVSP/kingair_propeller.vsp3"
START_TIME_FILE="/tmp/task_start_timestamp"

echo "=== Exporting result for openvsp_propeller_blade_design ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush writes
kill_openvsp

# Read start time
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")

python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
task_start = int('$TASK_START')

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'task_start': task_start,
    'file_exists': exists,
    'file_size': size,
    'file_content': content,
    'mtime': mtime,
    'file_created_during_task': mtime >= task_start if exists else False
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported Result: file_exists={exists}, size={size}, valid_time={result['file_created_during_task']}")
PYEOF

echo "=== Export complete ==="