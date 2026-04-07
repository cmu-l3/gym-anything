#!/bin/bash
# Export script for openvsp_wake_downwash_penalty task
# Captures the tandem model file, execution status of VSPAero, and the report

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_wake_downwash_penalty_result.json"

echo "=== Exporting result for openvsp_wake_downwash_penalty ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks and flush buffers
kill_openvsp

python3 << 'PYEOF'
import json
import os
import glob

models_dir = '/home/ga/Documents/OpenVSP'
desktop = '/home/ga/Desktop'

try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        start_ts = int(f.read().strip())
except Exception:
    start_ts = 0

vsp3_path = os.path.join(models_dir, 'tandem_wake.vsp3')
vsp3_exists = os.path.isfile(vsp3_path)
vsp3_content = ''
if vsp3_exists:
    with open(vsp3_path, 'r', errors='replace') as f:
        vsp3_content = f.read()

# Check for polar or history file to verify VSPAero executed during this session
vspaero_run = False
polar_files = [f for f in glob.glob(os.path.join(models_dir, '**', '*.polar'), recursive=True) 
               if os.path.getmtime(f) > start_ts]
hist_files = [f for f in glob.glob(os.path.join(models_dir, '**', '*.history'), recursive=True) 
              if os.path.getmtime(f) > start_ts]
if polar_files or hist_files:
    vspaero_run = True

report_path = os.path.join(desktop, 'wake_penalty_report.txt')
report_exists = os.path.isfile(report_path)
report_content = ''
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

result = {
    'vsp3_exists': vsp3_exists,
    'vsp3_content': vsp3_content,
    'vspaero_run': vspaero_run,
    'report_exists': report_exists,
    'report_content': report_content
}

with open('/tmp/openvsp_wake_downwash_penalty_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

echo "=== Export complete ==="