#!/bin/bash
# Export script for openvsp_blended_wing_body task
# Copies bwb_concept.vsp3 content for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/bwb_task_result.json"
MODEL_PATH="$MODELS_DIR/bwb_concept.vsp3"
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "=== Exporting result for openvsp_blended_wing_body ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP so file handles are released
kill_openvsp

python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
start_time = int('$START_TIME')
exists = os.path.isfile(model_path)

size = 0
mtime = 0
content = ''

if exists:
    size = os.path.getsize(model_path)
    mtime = int(os.path.getmtime(model_path))
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

# Anti-gaming: Ensure file was created/modified during the task
created_during_task = mtime >= start_time if exists else False

result = {
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'task_start_time': start_time,
    'created_during_task': created_during_task,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result exported: exists={exists}, size={size}, valid_time={created_during_task}")
PYEOF

echo "=== Export complete ==="