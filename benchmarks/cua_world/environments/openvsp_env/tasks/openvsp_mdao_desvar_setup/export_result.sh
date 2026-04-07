#!/bin/bash
# Export script for openvsp_mdao_desvar_setup task
# Records file metadata and captures the current .vsp3 content and report for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_mdao_desvar_setup_result.json"
MODEL_PATH="/home/ga/Documents/OpenVSP/eCRM001_mdao.vsp3"
REPORT_PATH="/home/ga/Desktop/desvar_summary.txt"

echo "=== Exporting result for openvsp_mdao_desvar_setup ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush file buffers
kill_openvsp

# Create JSON export safely using Python to handle encoding/escaping
python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
report_path = '$REPORT_PATH'
task_start = $TASK_START
task_end = $TASK_END

result = {
    'task_start': task_start,
    'task_end': task_end,
    'model_exists': False,
    'model_size': 0,
    'model_mtime': 0,
    'model_content': '',
    'report_exists': False,
    'report_size': 0,
    'report_content': ''
}

if os.path.isfile(model_path):
    result['model_exists'] = True
    result['model_size'] = os.path.getsize(model_path)
    result['model_mtime'] = int(os.path.getmtime(model_path))
    with open(model_path, 'r', errors='replace') as f:
        result['model_content'] = f.read()

if os.path.isfile(report_path):
    result['report_exists'] = True
    result['report_size'] = os.path.getsize(report_path)
    with open(report_path, 'r', errors='replace') as f:
        result['report_content'] = f.read()

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported: model_exists={result['model_exists']}, report_exists={result['report_exists']}")
PYEOF

echo "=== Export complete ==="