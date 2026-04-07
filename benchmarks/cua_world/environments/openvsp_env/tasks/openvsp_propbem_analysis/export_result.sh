#!/bin/bash
# Export script for openvsp_propbem_analysis task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_propbem_result.json"

echo "=== Exporting result for openvsp_propbem_analysis ==="

# Take final screenshot before closing
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release open file handles
kill_openvsp

# Read task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Package results into JSON for the verifier
python3 << PYEOF
import json
import os
import glob

exports_dir = '/home/ga/Documents/OpenVSP/exports'
models_dir = '/home/ga/Documents/OpenVSP'
desktop = '/home/ga/Desktop'
task_start = int($TASK_START)

result = {
    'task_start_time': task_start,
    'model_saved': False,
    'model_content': '',
    'csv_exists': False,
    'csv_content': '',
    'csv_created_during_task': False,
    'report_exists': False,
    'report_content': ''
}

# 1. Locate saved .vsp3 model (prefer expected name, fallback to any new .vsp3)
expected_model = os.path.join(exports_dir, '3blade_prop.vsp3')
model_path = expected_model if os.path.isfile(expected_model) else None

if not model_path:
    # Fallback: look for newly modified .vsp3 files in exports
    vsp3_files = glob.glob(os.path.join(exports_dir, '*.vsp3'))
    new_vsp3s = [f for f in vsp3_files if os.path.getmtime(f) > task_start]
    if new_vsp3s:
        new_vsp3s.sort(key=os.path.getmtime, reverse=True)
        model_path = new_vsp3s[0]

if model_path:
    result['model_saved'] = True
    with open(model_path, 'r', errors='replace') as f:
        result['model_content'] = f.read()

# 2. Locate PropBEM CSV output
csv_files = glob.glob(os.path.join(exports_dir, '*PropBEM*.csv')) + glob.glob(os.path.join(models_dir, '*PropBEM*.csv'))
new_csvs = [f for f in csv_files if os.path.getmtime(f) > task_start]

if new_csvs:
    new_csvs.sort(key=os.path.getmtime, reverse=True)
    target_csv = new_csvs[0]
    result['csv_exists'] = True
    result['csv_created_during_task'] = True
    with open(target_csv, 'r', errors='replace') as f:
        result['csv_content'] = f.read()

# 3. Locate summary report
report_path = os.path.join(desktop, 'prop_report.txt')
if os.path.isfile(report_path):
    result['report_exists'] = True
    with open(report_path, 'r', errors='replace') as f:
        result['report_content'] = f.read()

# Write JSON
with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported: Model saved={result['model_saved']}, CSV exists={result['csv_exists']}, Report exists={result['report_exists']}")
PYEOF

echo "=== Export complete ==="