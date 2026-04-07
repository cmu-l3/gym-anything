#!/bin/bash
# Export script for openvsp_mass_cg_balance task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting result for openvsp_mass_cg_balance ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP
kill_openvsp

python3 << 'PYEOF'
import json
import os

exports_dir = '/home/ga/Documents/OpenVSP/exports'
models_dir = '/home/ga/Documents/OpenVSP'
desktop = '/home/ga/Desktop'

massprops_path = os.path.join(exports_dir, 'eCRM001_massprops.txt')
report_path = os.path.join(desktop, 'mass_balance_report.txt')

mp_paths = []
if os.path.isfile(massprops_path):
    mp_paths.append(massprops_path)

for root, dirs, files in os.walk(models_dir):
    for f in files:
        if ('massprop' in f.lower() or 'mass' in f.lower()) and f.endswith('.txt'):
            p = os.path.join(root, f)
            if p not in mp_paths:
                mp_paths.append(p)

mp_exists = False
mp_content = ''
mp_mtime = 0

if mp_paths:
    mp_paths.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    best_mp = mp_paths[0]
    mp_exists = True
    mp_mtime = int(os.path.getmtime(best_mp))
    with open(best_mp, 'r', errors='replace') as f:
        mp_content = f.read()

report_exists = os.path.isfile(report_path)
report_content = ''
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

task_start = 0
if os.path.exists('/tmp/task_start_timestamp'):
    with open('/tmp/task_start_timestamp', 'r') as f:
        try:
            task_start = int(f.read().strip())
        except ValueError:
            pass

result = {
    'massprops_exists': mp_exists,
    'massprops_content': mp_content[:5000],
    'massprops_mtime': mp_mtime,
    'report_exists': report_exists,
    'report_content': report_content,
    'task_start': task_start
}

with open('/tmp/openvsp_mass_cg_balance_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported MassProps: exists={mp_exists}, Report: exists={report_exists}")
PYEOF

echo "=== Export complete ==="