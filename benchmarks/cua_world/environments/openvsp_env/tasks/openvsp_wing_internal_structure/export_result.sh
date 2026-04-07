#!/bin/bash
# Export script for openvsp_wing_internal_structure

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_wing_internal_structure_result.json"
OUTPUT_PATH="$MODELS_DIR/eCRM-001_structural.vsp3"

echo "=== Exporting result for openvsp_wing_internal_structure ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release any file locks
kill_openvsp

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check if file exists and extract info
python3 << PYEOF
import json, os

output_path = '$OUTPUT_PATH'
exists = os.path.isfile(output_path)
size = os.path.getsize(output_path) if exists else 0
mtime = int(os.path.getmtime(output_path)) if exists else 0
content = ''

if exists:
    with open(output_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result written: exists={exists}, size={size}")
PYEOF

echo "=== Export complete ==="