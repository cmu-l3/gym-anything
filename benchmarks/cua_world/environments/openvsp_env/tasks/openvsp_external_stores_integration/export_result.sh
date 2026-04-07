#!/bin/bash
# Export script for openvsp_external_stores_integration task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_stores_result.json"
MODEL_PATH="/home/ga/Documents/OpenVSP/eCRM001_military.vsp3"
REPORT_PATH="/home/ga/Desktop/stores_report.txt"
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "=== Exporting result for openvsp_external_stores_integration ==="

# Take final screenshot before closing
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush file writes
kill_openvsp

# Read file data using Python and save to JSON
python3 << PYEOF
import json
import os

model_path = '${MODEL_PATH}'
report_path = '${REPORT_PATH}'
start_time = ${START_TIME}

# Model file data
model_exists = os.path.isfile(model_path)
model_mtime = int(os.path.getmtime(model_path)) if model_exists else 0
model_size = os.path.getsize(model_path) if model_exists else 0
model_content = ''
if model_exists:
    with open(model_path, 'r', errors='replace') as f:
        model_content = f.read()

# Report file data
report_exists = os.path.isfile(report_path)
report_mtime = int(os.path.getmtime(report_path)) if report_exists else 0
report_content = ''
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

result = {
    'task_start_time': start_time,
    'model_exists': model_exists,
    'model_mtime': model_mtime,
    'model_size': model_size,
    'model_content': model_content,
    'report_exists': report_exists,
    'report_mtime': report_mtime,
    'report_content': report_content
}

with open('${RESULT_FILE}', 'w') as f:
    json.dump(result, f)

print(f"Exported Model: exists={model_exists}, size={model_size}")
print(f"Exported Report: exists={report_exists}, len={len(report_content)}")
PYEOF

echo "=== Export complete ==="