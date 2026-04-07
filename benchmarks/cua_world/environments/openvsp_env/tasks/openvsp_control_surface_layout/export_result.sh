#!/bin/bash
# Export script for openvsp_control_surface_layout task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_control_surface_result.json"
OUTPUT_MODEL="/home/ga/Documents/OpenVSP/eCRM001_with_controls.vsp3"
START_TIME_FILE="/tmp/task_start_timestamp"

echo "=== Exporting result for openvsp_control_surface_layout ==="

# Take final screenshot as evidence
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks
kill_openvsp

# Generate JSON result using Python to safely read and escape XML content
python3 << PYEOF
import json
import os

output_model = '$OUTPUT_MODEL'
start_time_file = '$START_TIME_FILE'

# Get start time
task_start = 0
if os.path.exists(start_time_file):
    with open(start_time_file, 'r') as f:
        try:
            task_start = int(f.read().strip())
        except ValueError:
            pass

exists = os.path.isfile(output_model)
size = os.path.getsize(output_model) if exists else 0
mtime = int(os.path.getmtime(output_model)) if exists else 0

content = ""
if exists and size > 0:
    # Read file content safely
    with open(output_model, 'r', errors='replace') as f:
        content = f.read()

# Determine if the file was created/modified during the task
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

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported result: file_exists={exists}, size={size}, created_during_task={created_during_task}")
PYEOF

echo "=== Export complete ==="