#!/bin/bash
# Export script for openvsp_nacelle_integration task
# Copies the target output file metadata and content for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_nacelle_integration_result.json"
TARGET_FILE="$MODELS_DIR/eCRM-001_with_nacelles.vsp3"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "=== Exporting result for openvsp_nacelle_integration ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP so file handles are fully released and flushed to disk
kill_openvsp

# Export file data to JSON using Python
python3 << PYEOF
import json, os

target_path = '$TARGET_FILE'
exists = os.path.isfile(target_path)
size = os.path.getsize(target_path) if exists else 0
mtime = int(os.path.getmtime(target_path)) if exists else 0
content = ''

if exists:
    with open(target_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_size': size,
    'mtime': mtime,
    'task_start': int('$TASK_START'),
    'file_content': content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result written: exists={exists}, size={size} bytes, mtime={mtime}")
PYEOF

echo "=== Export complete ==="