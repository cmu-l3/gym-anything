#!/bin/bash
# Export script for openvsp_suboff_cruciform_tail task
set -e

echo "=== Exporting result for openvsp_suboff_cruciform_tail ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_suboff_tail_result.json"
EXPECTED_FILE="$MODELS_DIR/SUBOFF_cruciform.vsp3"

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png ga

# 2. Kill OpenVSP to release file locks
kill_openvsp

# 3. Gather result data using Python
python3 << PYEOF
import json
import os

expected_file = '$EXPECTED_FILE'
start_time_file = '/tmp/task_start_timestamp'

# Read task start time
task_start_time = 0
try:
    with open(start_time_file, 'r') as f:
        task_start_time = int(f.read().strip())
except Exception:
    pass

# Check output file
file_exists = os.path.isfile(expected_file)
file_size = os.path.getsize(expected_file) if file_exists else 0
mtime = int(os.path.getmtime(expected_file)) if file_exists else 0

file_content = ""
if file_exists:
    with open(expected_file, 'r', errors='replace') as f:
        file_content = f.read()

result = {
    'task_start_time': task_start_time,
    'file_exists': file_exists,
    'file_size': file_size,
    'file_mtime': mtime,
    'file_created_during_task': (mtime > task_start_time) if file_exists else False,
    'file_content': file_content
}

# Write safely
temp_out = '/tmp/result_temp.json'
with open(temp_out, 'w') as f:
    json.dump(result, f)

os.replace(temp_out, '$RESULT_FILE')
os.chmod('$RESULT_FILE', 0o666)

print(f"Exported JSON: exists={file_exists}, created_during_task={result['file_created_during_task']}")
PYEOF

echo "=== Export complete ==="