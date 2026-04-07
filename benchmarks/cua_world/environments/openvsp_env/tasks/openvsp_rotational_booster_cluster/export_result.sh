#!/bin/bash
# Export script for openvsp_rotational_booster_cluster task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_rotational_booster_result.json"
MODEL_PATH="$MODELS_DIR/heavy_launch_vehicle.vsp3"
START_TIME_FILE="/tmp/task_start_timestamp"

echo "=== Exporting result for openvsp_rotational_booster_cluster ==="

# Take final trajectory screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to ensure file buffers are flushed and locks released
kill_openvsp

# Extract data into JSON for the Python verifier
python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
start_time_file = '$START_TIME_FILE'

# Retrieve task start time
task_start = 0
if os.path.isfile(start_time_file):
    with open(start_time_file, 'r') as f:
        try:
            task_start = int(f.read().strip())
        except ValueError:
            pass

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0
content = ''

if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'task_start': task_start,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Export Result: exists={exists}, size={size} bytes, mtime={mtime}")
PYEOF

echo "=== Export complete ==="