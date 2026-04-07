#!/bin/bash
# Export script for openvsp_uuv_hydrodynamic_model task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_uuv_hydro_result.json"
MODEL_PATH="$MODELS_DIR/uuv_model.vsp3"
REPORT_PATH="/home/ga/Desktop/uuv_hydro_report.txt"

echo "=== Exporting result for openvsp_uuv_hydrodynamic_model ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks and flush saves
kill_openvsp

# Use python to cleanly encode file contents and metadata
python3 << PYEOF
import json
import os

model_path = '$MODEL_PATH'
report_path = '$REPORT_PATH'
start_time_path = '/tmp/task_start_timestamp'

# Get start time
task_start = 0
try:
    with open(start_time_path, 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    pass

# Check VSP3
vsp_exists = os.path.isfile(model_path)
vsp_size = os.path.getsize(model_path) if vsp_exists else 0
vsp_mtime = int(os.path.getmtime(model_path)) if vsp_exists else 0
vsp_created_during_task = vsp_mtime > task_start if vsp_exists else False

vsp_content = ""
if vsp_exists:
    with open(model_path, 'r', errors='replace') as f:
        vsp_content = f.read()

# Check Report
report_exists = os.path.isfile(report_path)
report_mtime = int(os.path.getmtime(report_path)) if report_exists else 0
report_created_during_task = report_mtime > task_start if report_exists else False

report_content = ""
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

result = {
    'task_start': task_start,
    'vsp_exists': vsp_exists,
    'vsp_size': vsp_size,
    'vsp_mtime': vsp_mtime,
    'vsp_created_during_task': vsp_created_during_task,
    'vsp_content': vsp_content,
    'report_exists': report_exists,
    'report_created_during_task': report_created_during_task,
    'report_content': report_content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Result Exported: VSP3 Exists={vsp_exists}, Report Exists={report_exists}")
PYEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="