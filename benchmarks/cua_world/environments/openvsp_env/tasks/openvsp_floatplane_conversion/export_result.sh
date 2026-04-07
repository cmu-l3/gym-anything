#!/bin/bash
# Export script for openvsp_floatplane_conversion task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_floatplane_result.json"
MODEL_PATH="$MODELS_DIR/floatplane_variant.vsp3"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "=== Exporting result for openvsp_floatplane_conversion ==="

# Take final screenshot BEFORE killing OpenVSP for visual verification
take_screenshot /tmp/task_final.png
sleep 1

# Kill OpenVSP to release file locks and flush saves
kill_openvsp

# Check if model file exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "WARNING: target file $MODEL_PATH not found."
    python3 -c "
import json
with open('$RESULT_FILE', 'w') as f:
    json.dump({'file_exists': False, 'mtime': 0, 'file_content': '', 'task_start': $START_TIME}, f)
"
    exit 0
fi

# Write result JSON using Python to safely escape XML content
python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
start_time = int('$START_TIME')

file_content_raw = ""
if os.path.exists(model_path):
    with open(model_path, 'r', errors='replace') as f:
        file_content_raw = f.read()

result = {
    'file_exists': os.path.exists(model_path),
    'mtime': int(os.path.getmtime(model_path)) if os.path.exists(model_path) else 0,
    'file_size': os.path.getsize(model_path) if os.path.exists(model_path) else 0,
    'file_content': file_content_raw,
    'task_start': start_time
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result written: file_exists={result['file_exists']}, size={result['file_size']} bytes")
PYEOF

echo "=== Export complete ==="