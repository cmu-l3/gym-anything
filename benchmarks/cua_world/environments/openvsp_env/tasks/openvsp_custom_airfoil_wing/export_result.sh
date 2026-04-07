#!/bin/bash
# Export script for openvsp_custom_airfoil_wing task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_custom_airfoil_wing_result.json"
MODEL_PATH="$MODELS_DIR/turbine_blade.vsp3"

echo "=== Exporting result for openvsp_custom_airfoil_wing ==="

# Check if OpenVSP is running
APP_RUNNING=$(pgrep -f "$OPENVSP_BIN" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Kill OpenVSP to flush writes
kill_openvsp

# Capture Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect model file metadata and content
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
result_file = '$RESULT_FILE'
task_start = int('$TASK_START')
app_running = '$APP_RUNNING' == 'true'

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0
file_created_during_task = (mtime > task_start) if exists else False

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'task_start_time': task_start,
    'app_was_running': app_running,
    'file_exists': exists,
    'file_size': size,
    'file_mtime': mtime,
    'file_created_during_task': file_created_during_task,
    'file_content': content
}

with open(result_file, 'w') as f:
    json.dump(result, f)

print(f"Exported: exists={exists}, size={size}, created_during_task={file_created_during_task}")
PYEOF

echo "=== Export complete ==="