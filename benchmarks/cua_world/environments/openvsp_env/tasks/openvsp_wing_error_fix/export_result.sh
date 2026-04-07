#!/bin/bash
# Export script for openvsp_wing_error_fix task
# Records file metadata and captures the current .vsp3 content for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_wing_error_fix_result.json"
MODEL_PATH="$MODELS_DIR/cessna210_corrupt.vsp3"

echo "=== Exporting result for openvsp_wing_error_fix ==="

# Take final screenshot before killing OpenVSP
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP so file is fully saved (no exclusive lock)
kill_openvsp

# Check if model file exists
if [ ! -f "$MODEL_PATH" ]; then
    write_result_json '{"file_exists": false, "file_content": "", "mtime": 0}' "$RESULT_FILE"
    echo "ERROR: model file not found at $MODEL_PATH"
    exit 0
fi

# Get file modification time (integer seconds)
MTIME=$(stat -c %Y "$MODEL_PATH" 2>/dev/null || echo "0")

# Read the file content (the verifier will parse XML from this)
FILE_CONTENT=$(cat "$MODEL_PATH" | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')

# Write result JSON
python3 << PYEOF
import json, os

file_content_raw = open('$MODEL_PATH', 'r').read()
result = {
    'file_exists': True,
    'mtime': int(os.path.getmtime('$MODEL_PATH')),
    'file_size': os.path.getsize('$MODEL_PATH'),
    'file_content': file_content_raw
}
with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)
print(f"Result written: file_exists={result['file_exists']}, size={result['file_size']}")
PYEOF

echo "=== Export complete ==="
