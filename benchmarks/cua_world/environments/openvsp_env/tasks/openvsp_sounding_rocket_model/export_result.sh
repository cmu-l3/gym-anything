#!/bin/bash
# Export script for openvsp_sounding_rocket_model task
# Captures the saved .vsp3 content and metadata for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_sounding_rocket_result.json"
MODEL_PATH="$MODELS_DIR/sounding_rocket.vsp3"

echo "=== Exporting result for openvsp_sounding_rocket_model ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release any file locks
kill_openvsp

# Extract data using Python and save to JSON
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
task_start = $TASK_START
task_end = $TASK_END

file_exists = os.path.isfile(model_path)
file_size = os.path.getsize(model_path) if file_exists else 0
mtime = int(os.path.getmtime(model_path)) if file_exists else 0

created_during_task = False
if file_exists and mtime >= task_start:
    created_during_task = True

content = ''
if file_exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'task_start': task_start,
    'task_end': task_end,
    'file_exists': file_exists,
    'file_size': file_size,
    'mtime': mtime,
    'created_during_task': created_during_task,
    'file_content': content
}

temp_path = '/tmp/result_temp.json'
with open(temp_path, 'w') as f:
    json.dump(result, f)
PYEOF

# Move to final location safely
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp /tmp/result_temp.json "$RESULT_FILE" 2>/dev/null || sudo cp /tmp/result_temp.json "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f /tmp/result_temp.json

echo "Result saved to $RESULT_FILE"
echo "=== Export complete ==="