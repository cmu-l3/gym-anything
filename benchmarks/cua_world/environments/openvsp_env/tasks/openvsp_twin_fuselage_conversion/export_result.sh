#!/bin/bash
# Export script for openvsp_twin_fuselage_conversion task
# Records file metadata and captures the current .vsp3 content for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_twin_fuselage_result.json"
MODEL_PATH="$MODELS_DIR/twin_fuselage_launcher.vsp3"

echo "=== Exporting result for openvsp_twin_fuselage_conversion ==="

# Take final screenshot before killing OpenVSP
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP so the file is fully flushed and saved
kill_openvsp

# Read task start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Create JSON result using Python to safely escape file contents
python3 << PYEOF
import json, os, sys

model_path = '$MODEL_PATH'
task_start = int('$TASK_START')

exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
mtime = int(os.path.getmtime(model_path)) if exists else 0

content = ''
if exists:
    try:
        with open(model_path, 'r', errors='replace') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading file: {e}", file=sys.stderr)

result = {
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'task_start': task_start,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Export successful. File exists: {exists}, Size: {size} bytes")
PYEOF

echo "=== Export complete ==="