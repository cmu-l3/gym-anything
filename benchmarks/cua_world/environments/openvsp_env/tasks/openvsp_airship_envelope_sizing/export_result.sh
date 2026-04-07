#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting result for openvsp_airship_envelope_sizing ==="

# Capture final visual evidence
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks
kill_openvsp

python3 << 'PYEOF'
import json, os

vsp_path = '/home/ga/Documents/OpenVSP/haps_airship.vsp3'
report_path = '/home/ga/Desktop/airship_report.txt'
start_ts_path = '/tmp/task_start_timestamp'

start_ts = 0
if os.path.exists(start_ts_path):
    with open(start_ts_path, 'r') as f:
        try:
            start_ts = int(f.read().strip())
        except ValueError:
            pass

vsp_exists = os.path.exists(vsp_path)
vsp_mtime = int(os.path.getmtime(vsp_path)) if vsp_exists else 0
vsp_content = ""
if vsp_exists:
    with open(vsp_path, 'r', errors='replace') as f:
        vsp_content = f.read()

report_exists = os.path.exists(report_path)
report_mtime = int(os.path.getmtime(report_path)) if report_exists else 0
report_content = ""
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

result = {
    'task_start': start_ts,
    'vsp_exists': vsp_exists,
    'vsp_mtime': vsp_mtime,
    'vsp_content': vsp_content,
    'report_exists': report_exists,
    'report_mtime': report_mtime,
    'report_content': report_content
}

with open('/tmp/openvsp_airship_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

echo "=== Export complete ==="