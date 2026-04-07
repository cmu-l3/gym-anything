#!/bin/bash
# Export script for openvsp_landing_gear_layout task
# Dumps report and saved model XML for verification

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_landing_gear_layout_result.json"
MODEL_PATH="$MODELS_DIR/eCRM001_geared.vsp3"
REPORT_PATH="/home/ga/Desktop/gear_report.txt"

echo "=== Exporting result for openvsp_landing_gear_layout ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks
kill_openvsp

python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
report_path = '$REPORT_PATH'
task_start = 0

try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        task_start = int(f.read().strip())
except:
    pass

model_exists = os.path.isfile(model_path)
model_content = ''
if model_exists:
    with open(model_path, 'r', errors='replace') as f:
        model_content = f.read()

report_exists = os.path.isfile(report_path)
report_content = ''
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

result = {
    'task_start': task_start,
    'model_exists': model_exists,
    'model_mtime': int(os.path.getmtime(model_path)) if model_exists else 0,
    'model_content': model_content,
    'report_exists': report_exists,
    'report_content': report_content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported model_exists={model_exists}, report_exists={report_exists}")
PYEOF

echo "=== Export complete ==="