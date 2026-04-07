#!/bin/bash
# Export script for openvsp_uam_quadrotor_layout task
# Copies nasa_quadrotor.vsp3 content for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_uam_quadrotor_layout_result.json"
MODEL_PATH="$MODELS_DIR/nasa_quadrotor.vsp3"

echo "=== Exporting result for openvsp_uam_quadrotor_layout ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP so file buffers are fully flushed and lock released
kill_openvsp

python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

# Read the start timestamp to verify the file was generated during the session
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        start_time = int(f.read().strip())
except Exception:
    start_time = 0

mtime = int(os.path.getmtime(model_path)) if exists else 0

result = {
    'file_exists': exists,
    'file_size': size,
    'file_content': content,
    'mtime': mtime,
    'start_time': start_time,
    'created_during_task': mtime >= start_time if exists else False
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result: file_exists={exists}, size={size}, created_during_task={result['created_during_task']}")
PYEOF

echo "=== Export complete ==="