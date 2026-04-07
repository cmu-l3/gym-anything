#!/bin/bash
# Export script for openvsp_evtol_lift_boom_integration task
# Saves model metadata and extracts the XML content for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_evtol_boom_result.json"
TARGET_MODEL="$MODELS_DIR/ecrm_evtol.vsp3"

echo "=== Exporting result for openvsp_evtol_lift_boom_integration ==="

# Take final screenshot before doing anything
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to ensure the file is completely written and file handles are released
kill_openvsp

# Extract the file and package into a JSON result
python3 << PYEOF
import json, os

model_path = '$TARGET_MODEL'
exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0

content = ''
if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        start_time = int(f.read().strip())
except Exception:
    start_time = 0

result = {
    'file_exists': exists,
    'file_size': size,
    'file_content': content,
    'mtime': int(os.path.getmtime(model_path)) if exists else 0,
    'start_time': start_time
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result exported: file_exists={exists}, size={size}")
PYEOF

echo "=== Export complete ==="