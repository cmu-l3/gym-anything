#!/bin/bash
# Export script for openvsp_inverted_gull_wing task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/task_result.json"
MODEL_PATH="$MODELS_DIR/inverted_gull_wing.vsp3"

echo "=== Exporting result for openvsp_inverted_gull_wing ==="

# Record end time and check application state
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
APP_RUNNING=$(pgrep -f "vsp" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Kill OpenVSP to release file locks and ensure buffer flushes
kill_openvsp

python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0
task_start = int('$TASK_START')

# Determine if the file was created during the task window
created_during_task = exists and (mtime >= task_start)

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'task_start': task_start,
    'task_end': int('$TASK_END'),
    'app_was_running': $APP_RUNNING,
    'file_exists': exists,
    'file_size': size,
    'file_mtime': mtime,
    'created_during_task': created_during_task,
    'file_content': content
}

# Write safely via temp file
import tempfile
import shutil
fd, temp_path = tempfile.mkstemp(suffix='.json')
with os.fdopen(fd, 'w') as f:
    json.dump(result, f)
shutil.copy(temp_path, '$RESULT_FILE')
os.chmod('$RESULT_FILE', 0o666)
os.unlink(temp_path)

print(f"Result saved: exists={exists}, created_during_task={created_during_task}, size={size}")
PYEOF

echo "=== Export complete ==="