#!/bin/bash
# Export script for openvsp_variable_sweep_kinematics
# Extracts the final VSP3 content and metadata for programmatic verification.

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_variable_sweep_kinematics_result.json"
TARGET_MODEL="$MODELS_DIR/fx_swept.vsp3"
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "=== Exporting result for openvsp_variable_sweep_kinematics ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Check if OpenVSP is running
APP_RUNNING=$(pgrep -f "$OPENVSP_BIN" > /dev/null && echo "true" || echo "false")

# Kill OpenVSP to release file locks
kill_openvsp

# Package the results securely using Python
python3 << PYEOF
import json, os

model_path = '$TARGET_MODEL'
exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0
content = ''

if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'task_start': $START_TIME,
    'file_exists': exists,
    'file_size': size,
    'file_mtime': mtime,
    'file_content': content,
    'app_was_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final_screenshot.png'
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)
print(f"Result Exported: file_exists={exists}, size={size} bytes")
PYEOF

echo "=== Export complete ==="