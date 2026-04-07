#!/bin/bash
echo "=== Exporting result for openvsp_ekranoplan_wig_concept ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/task_result.json"
MODEL_PATH="/home/ga/Documents/OpenVSP/wig_concept.vsp3"
START_TIME_FILE="/tmp/task_start_timestamp"

# Take final screenshot before altering state
take_screenshot /tmp/task_final.png

# Kill OpenVSP so any open files are flushed and handles released
kill_openvsp

# Read task start time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# Package file metadata and content into JSON safely
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
result_file = '$RESULT_FILE'
task_start = int('$TASK_START')

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0
content = ''

if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

# Anti-gaming check: File must have been created/modified after task started
created_during_task = False
if exists and mtime >= task_start:
    created_during_task = True

result = {
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'task_start': task_start,
    'created_during_task': created_during_task,
    'file_content': content
}

with open(result_file, 'w') as f:
    json.dump(result, f)

print(f"Exported: exists={exists}, size={size}, created_during_task={created_during_task}")
PYEOF

echo "=== Export complete ==="