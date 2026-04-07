#!/bin/bash
# Export script for openvsp_wet_wing_fuel_volume task
# Captures the saved .vsp3 content and the written report

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_wet_wing_result.json"
MODEL_PATH="/home/ga/Documents/OpenVSP/eCRM001_wet_wing.vsp3"
REPORT_PATH="/home/ga/Desktop/fuel_capacity_report.txt"

echo "=== Exporting result for openvsp_wet_wing_fuel_volume ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release any file locks
kill_openvsp

# Extract data using Python to guarantee clean JSON serialization
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
report_path = '$REPORT_PATH'

# Extract model file status and content
model_exists = os.path.isfile(model_path)
model_size = os.path.getsize(model_path) if model_exists else 0
model_content = ''
if model_exists:
    with open(model_path, 'r', errors='replace') as f:
        model_content = f.read()

# Extract report status and content
report_exists = os.path.isfile(report_path)
report_content = ''
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

result = {
    'model_exists': model_exists,
    'model_size': model_size,
    'model_content': model_content,
    'model_mtime': int(os.path.getmtime(model_path)) if model_exists else 0,
    'report_exists': report_exists,
    'report_content': report_content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported Model: exists={model_exists}, size={model_size}")
print(f"Exported Report: exists={report_exists}, length={len(report_content)}")
PYEOF

echo "=== Export complete ==="