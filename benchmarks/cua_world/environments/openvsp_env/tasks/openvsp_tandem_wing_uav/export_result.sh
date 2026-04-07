#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_tandem_wing_uav_result.json"
MODEL_PATH="$MODELS_DIR/tandem_wing_uav.vsp3"

echo "=== Exporting result for openvsp_tandem_wing_uav ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush writes and clear locks
kill_openvsp

python3 << PYEOF
import json
import os
import hashlib

model_path = '$MODEL_PATH'
start_timestamp_file = '/tmp/task_start_timestamp'

task_start = 0
if os.path.exists(start_timestamp_file):
    try:
        with open(start_timestamp_file, 'r') as f:
            task_start = int(f.read().strip())
    except:
        pass

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0
content = ''
md5_hash = ''

if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()
    with open(model_path, 'rb') as f:
        md5_hash = hashlib.md5(f.read()).hexdigest()

result = {
    'file_exists': exists,
    'file_size': size,
    'file_content': content,
    'mtime': mtime,
    'task_start': task_start,
    'md5': md5_hash
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result details exported: file_exists={exists}, size={size}, mtime={mtime}")
PYEOF

echo "=== Export complete ==="