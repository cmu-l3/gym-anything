#!/bin/bash
# Export script for openvsp_conformal_radome task
# Captures final screenshot, shuts down OpenVSP, and packages artifacts into a JSON result

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/task_result.json"
MODEL_PATH="$MODELS_DIR/eCRM001_satcom.vsp3"
REPORT_PATH="/home/ga/Desktop/radome_report.txt"

echo "=== Exporting result for openvsp_conformal_radome ==="

# Take final screenshot before killing the app
take_screenshot /tmp/task_final.png

# Kill OpenVSP to release file locks and ensure buffers are flushed
kill_openvsp

# Extract data using Python to guarantee safe JSON formatting
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
report_path = '$REPORT_PATH'

# Check Model File
model_exists = os.path.isfile(model_path)
model_size = os.path.getsize(model_path) if model_exists else 0
model_mtime = int(os.path.getmtime(model_path)) if model_exists else 0
model_content = ''
if model_exists:
    with open(model_path, 'r', errors='replace') as f:
        model_content = f.read()

# Check Report File
report_exists = os.path.isfile(report_path)
report_mtime = int(os.path.getmtime(report_path)) if report_exists else 0
report_content = ''
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

# Task Start Time
try:
    with open('/tmp/task_start_time', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

result = {
    'task_start_time': task_start,
    'model': {
        'exists': model_exists,
        'size': model_size,
        'mtime': model_mtime,
        'content': model_content
    },
    'report': {
        'exists': report_exists,
        'mtime': report_mtime,
        'content': report_content
    }
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result exported: Model exists={model_exists}, Report exists={report_exists}")
PYEOF

echo "=== Export complete ==="