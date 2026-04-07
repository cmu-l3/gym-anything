#!/bin/bash
# Export script for openvsp_sduct_integration task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_sduct_result.json"
EXPECTED_OUTPUT="/home/ga/Documents/OpenVSP/bizjet_trijet.vsp3"

echo "=== Exporting result for openvsp_sduct_integration ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Kill OpenVSP to release file locks and ensure recent saves are flushed to disk
kill_openvsp

# Prepare python script to export file metrics and content to JSON
python3 << PYEOF
import json, os, sys

model_path = '$EXPECTED_OUTPUT'
task_start = $TASK_START
task_end = $TASK_END

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0

# Check if file was created/modified during the task window
file_created_during_task = False
if exists and (mtime >= task_start):
    file_created_during_task = True

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'task_start': task_start,
    'task_end': task_end,
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'file_created_during_task': file_created_during_task,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)
    
print(f"Exported: exists={exists}, created_during_task={file_created_during_task}, size={size}")
PYEOF

echo "=== Export complete ==="