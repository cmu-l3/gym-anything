#!/bin/bash
# Export script for openvsp_joined_wing_config task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_joined_wing_config_result.json"
MODEL_PATH="$MODELS_DIR/box_wing_complete.vsp3"
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "=== Exporting result for openvsp_joined_wing_config ==="

# Capture final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush writes and release file lock
kill_openvsp
sleep 1

# Check if application was running
APP_RUNNING=$(pgrep -f "vsp" > /dev/null && echo "true" || echo "false")

python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
task_start_time = int('$TASK_START_TIME')
exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0
file_created_during_task = mtime >= task_start_time

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_size': size,
    'file_mtime': mtime,
    'file_created_during_task': file_created_during_task,
    'app_was_running': '$APP_RUNNING' == 'true',
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result JSON saved: file_exists={exists}, size={size}, created_during_task={file_created_during_task}")
PYEOF

echo "=== Export complete ==="