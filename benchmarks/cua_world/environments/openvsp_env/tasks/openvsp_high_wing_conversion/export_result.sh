#!/bin/bash
# Export script for openvsp_high_wing_conversion task
# Captures the baseline and modified OpenVSP model files for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/high_wing_result.json"
BASELINE_PATH="$MODELS_DIR/eCRM-001_wing_tail.vsp3"
MODIFIED_PATH="$MODELS_DIR/eCRM001_highwing.vsp3"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "=== Exporting result for openvsp_high_wing_conversion ==="

# Take final screenshot before closing
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush file writes and release locks
kill_openvsp

# Create JSON file with both baseline and modified file contents for verifier analysis
python3 << PYEOF
import json, os

baseline_path = '$BASELINE_PATH'
modified_path = '$MODIFIED_PATH'
task_start_time = int('$TASK_START_TIME')

result = {
    'task_start_time': task_start_time,
    'modified_exists': False,
    'modified_mtime': 0,
    'modified_size': 0,
    'baseline_content': '',
    'modified_content': ''
}

if os.path.exists(baseline_path):
    with open(baseline_path, 'r', errors='replace') as f:
        result['baseline_content'] = f.read()

if os.path.exists(modified_path):
    result['modified_exists'] = True
    result['modified_mtime'] = int(os.path.getmtime(modified_path))
    result['modified_size'] = os.path.getsize(modified_path)
    with open(modified_path, 'r', errors='replace') as f:
        result['modified_content'] = f.read()

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result written: modified_exists={result['modified_exists']}, size={result['modified_size']}")
PYEOF

echo "=== Export complete ==="