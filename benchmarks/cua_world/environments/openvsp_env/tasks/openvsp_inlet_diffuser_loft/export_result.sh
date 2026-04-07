#!/bin/bash
# Export script for openvsp_inlet_diffuser_loft task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_inlet_result.json"
MODEL_PATH="$MODELS_DIR/ramjet_inlet.vsp3"
REPORT_PATH="/home/ga/Desktop/diffuser_report.txt"

echo "=== Exporting result for openvsp_inlet_diffuser_loft ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP so file handles are released and buffered data is written
kill_openvsp

# Extract data using Python and save to JSON
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
report_path = '$REPORT_PATH'
task_start_time = 0

try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        task_start_time = int(f.read().strip())
except:
    pass

model_exists = os.path.isfile(model_path)
model_size = os.path.getsize(model_path) if model_exists else 0
model_mtime = int(os.path.getmtime(model_path)) if model_exists else 0
model_content = ''
if model_exists:
    with open(model_path, 'r', errors='replace') as f:
        model_content = f.read()

report_exists = os.path.isfile(report_path)
report_size = os.path.getsize(report_path) if report_exists else 0
report_mtime = int(os.path.getmtime(report_path)) if report_exists else 0
report_content = ''
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

result = {
    'task_start_time': task_start_time,
    'model_exists': model_exists,
    'model_size': model_size,
    'model_mtime': model_mtime,
    'model_content': model_content,
    'report_exists': report_exists,
    'report_size': report_size,
    'report_mtime': report_mtime,
    'report_content': report_content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported: Model Exists={model_exists}, Report Exists={report_exists}")
PYEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "=== Export complete ==="