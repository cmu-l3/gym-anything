#!/bin/bash
# Export script for openvsp_shuttle_stack_integration
# Captures the saved .vsp3 content and file metadata for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_shuttle_result.json"
TARGET_MODEL="$MODELS_DIR/sts_ascent_stack.vsp3"

echo "=== Exporting result for openvsp_shuttle_stack_integration ==="

# Take final screenshot before closing
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to ensure file buffers are flushed and locks released
kill_openvsp

# Gather file data via Python and write securely to JSON
python3 << PYEOF
import json, os, time

model_path = '$TARGET_MODEL'
start_time_file = '/tmp/task_start_timestamp'

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0

try:
    with open(start_time_file, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'task_start': task_start,
    'file_created_during_task': mtime >= task_start if exists else False,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported Result: exists={exists}, size={size} bytes, created_during_task={result['file_created_during_task']}")
PYEOF

echo "=== Export complete ==="