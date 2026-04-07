#!/bin/bash
# Export script for openvsp_concorde_delta_wing task
# Takes screenshot, captures model file, and packages result JSON

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_concorde_result.json"
MODEL_PATH="$MODELS_DIR/concorde_wing.vsp3"
START_TIME_FILE="/tmp/task_start_time.txt"

echo "=== Exporting result for openvsp_concorde_delta_wing ==="

# Take final screenshot as visual evidence
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to ensure file buffers are flushed and locks released
kill_openvsp

# Use Python to safely parse file metadata and content into JSON
python3 << PYEOF
import json, os, time

model_path = '$MODEL_PATH'
start_time_file = '$START_TIME_FILE'

# Get task start time
try:
    with open(start_time_file, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0

file_created_during_task = False
if exists and task_start > 0 and mtime >= task_start:
    file_created_during_task = True

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'task_start': task_start,
    'file_created_during_task': file_created_during_task,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)
    
print(f"Exported: exists={exists}, created_during_task={file_created_during_task}, size={size}")
PYEOF

echo "=== Export complete ==="