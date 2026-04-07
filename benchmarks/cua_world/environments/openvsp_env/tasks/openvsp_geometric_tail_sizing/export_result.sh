#!/bin/bash
set -e
echo "=== Exporting Result for OpenVSP Geometric Tail Sizing ==="

source /workspace/scripts/task_utils.sh
RESULT_FILE="/tmp/openvsp_tail_sizing_result.json"

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush file buffers
kill_openvsp

# Read and package all relevant files
python3 << 'PYEOF'
import json
import os

models_dir = '/home/ga/Documents/OpenVSP'
initial_path = os.path.join(models_dir, 'aircraft_configuration.vsp3')
final_path = os.path.join(models_dir, 'aircraft_configuration_sized.vsp3')
report_path = '/home/ga/Desktop/sizing_report.txt'

result = {
    'initial_xml': '',
    'final_xml': '',
    'final_exists': False,
    'report_exists': False,
    'report_content': ''
}

if os.path.exists(initial_path):
    with open(initial_path, 'r', errors='replace') as f:
        result['initial_xml'] = f.read()

if os.path.exists(final_path):
    result['final_exists'] = True
    result['final_mtime'] = int(os.path.getmtime(final_path))
    with open(final_path, 'r', errors='replace') as f:
        result['final_xml'] = f.read()

if os.path.exists(report_path):
    result['report_exists'] = True
    with open(report_path, 'r', errors='replace') as f:
        result['report_content'] = f.read()

# Make sure task_start_timestamp is read to detect "Do Nothing" gaming
start_time_file = '/tmp/task_start_timestamp'
if os.path.exists(start_time_file):
    with open(start_time_file, 'r') as f:
        try:
            result['task_start'] = int(f.read().strip())
        except ValueError:
            result['task_start'] = 0

with open('/tmp/openvsp_tail_sizing_result.json', 'w') as f:
    json.dump(result, f)

print(f"Exported data. Final model exists: {result['final_exists']}, Report exists: {result['report_exists']}")
PYEOF

echo "=== Export complete ==="