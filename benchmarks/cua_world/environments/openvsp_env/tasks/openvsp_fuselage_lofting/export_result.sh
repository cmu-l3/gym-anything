#!/bin/bash
# Export script for openvsp_fuselage_lofting task
# Captures file metadata and content for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_fuselage_lofting_result.json"
MODEL_PATH="$MODELS_DIR/male_uav.vsp3"

echo "=== Exporting result for openvsp_fuselage_lofting ==="

# Take final screenshot before killing OpenVSP
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks and flush buffers
kill_openvsp

python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
content = ''

if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

task_start = 0
if os.path.exists('/tmp/task_start_timestamp'):
    try:
        with open('/tmp/task_start_timestamp', 'r') as f:
            task_start = int(f.read().strip())
    except ValueError:
        pass

result = {
    'file_exists': exists,
    'file_size': size,
    'file_content': content,
    'mtime': int(os.path.getmtime(model_path)) if exists else 0,
    'task_start': task_start
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Export successful. File exists: {exists}, Size: {size} bytes")
PYEOF

echo "=== Export complete ==="