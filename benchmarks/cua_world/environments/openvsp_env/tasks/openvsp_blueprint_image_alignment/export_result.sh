#!/bin/bash
# Export script for openvsp_blueprint_image_alignment task
set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_blueprint_alignment_result.json"
MODEL_PATH="$MODELS_DIR/p51_workspace.vsp3"
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "=== Exporting result for openvsp_blueprint_image_alignment ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush any unwritten file buffers
kill_openvsp

# Read and record the saved VSP3 file
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
result_file = '$RESULT_FILE'
start_time = int('$START_TIME')

file_exists = os.path.isfile(model_path)
mtime = int(os.path.getmtime(model_path)) if file_exists else 0
size = os.path.getsize(model_path) if file_exists else 0
created_during_task = mtime >= start_time if file_exists else False

content = ''
if file_exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': file_exists,
    'mtime': mtime,
    'size': size,
    'created_during_task': created_during_task,
    'file_content': content
}

with open(result_file, 'w') as f:
    json.dump(result, f)

print(f"Exported data: file_exists={file_exists}, size={size}, created_during_task={created_during_task}")
PYEOF

chmod 666 "$RESULT_FILE"
echo "=== Export complete ==="