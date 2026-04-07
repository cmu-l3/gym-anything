#!/bin/bash
# Export script for openvsp_stl_reverse_engineering task
set -e

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_stl_reverse_engineering_result.json"
MODEL_PATH="/home/ga/Documents/OpenVSP/reconstructed_wing.vsp3"

echo "=== Exporting result for openvsp_stl_reverse_engineering ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks
kill_openvsp

# Read and evaluate file
python3 << PYEOF
import json, os, sys

model_path = '$MODEL_PATH'
exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0
task_start = int('$TASK_START')

# Check anti-gaming: Was file created/modified DURING the task?
created_during_task = False
if exists and mtime > task_start:
    created_during_task = True

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_size': size,
    'file_mtime': mtime,
    'created_during_task': created_during_task,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result: file_exists={exists}, size={size}, valid_time={created_during_task}")
PYEOF

echo "=== Export complete ==="