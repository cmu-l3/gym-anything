#!/bin/bash
# Export script for openvsp_component_hierarchy task
# Records file metadata and content

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_component_hierarchy_result.json"
MODEL_PATH="$MODELS_DIR/assembled_jet.vsp3"

echo "=== Exporting result for openvsp_component_hierarchy ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush saves
kill_openvsp

# Record task timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
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
    'file_mtime': mtime,
    'task_start': int('$TASK_START'),
    'task_end': int('$TASK_END'),
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)
print(f"Result: file_exists={exists}, size={size}")
PYEOF

echo "=== Export complete ==="