#!/bin/bash
# Export script for openvsp_dep_propeller_layout task
# Captures the saved .vsp3 content and file metadata

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_dep_propeller_layout_result.json"
MODEL_PATH="$MODELS_DIR/dep_wing.vsp3"

echo "=== Exporting result for openvsp_dep_propeller_layout ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks and flush buffers
kill_openvsp

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

start_time = 0
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        start_time = int(f.read().strip())
except Exception:
    pass

result = {
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'start_time': start_time,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported Result: file_exists={exists}, size={size} bytes")
PYEOF

echo "=== Export complete ==="