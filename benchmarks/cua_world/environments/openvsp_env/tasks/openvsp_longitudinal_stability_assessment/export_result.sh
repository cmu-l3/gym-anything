#!/bin/bash
# Export script for openvsp_longitudinal_stability_assessment task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_stability_result.json"

echo "=== Exporting result for openvsp_longitudinal_stability_assessment ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release any open file handles
kill_openvsp

# Extract data using Python and save to JSON for verifier
python3 << 'PYEOF'
import json, os, glob

models_dir = '/home/ga/Documents/OpenVSP'
desktop = '/home/ga/Desktop'
report_path = os.path.join(desktop, 'stability_report.txt')
model_path = os.path.join(models_dir, 'eCRM-001_stability.vsp3')

task_start = 0
if os.path.exists('/tmp/task_start_timestamp'):
    try:
        with open('/tmp/task_start_timestamp', 'r') as f:
            task_start = int(f.read().strip())
    except:
        pass

# 1. Check saved model
model_exists = os.path.isfile(model_path)
model_content = ''
model_mtime = 0
if model_exists:
    model_mtime = int(os.path.getmtime(model_path))
    try:
        with open(model_path, 'r', errors='replace') as f:
            model_content = f.read()
    except Exception:
        pass

# 2. Find .polar file (latest created after task start)
polar_paths = []
for root, dirs, files in os.walk(models_dir):
    for fname in files:
        if fname.endswith('.polar'):
            polar_paths.append(os.path.join(root, fname))

polar_content = ''
polar_exists = False
polar_path_found = ''

if polar_paths:
    # Use most recently modified polar file
    polar_paths.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    best_polar = polar_paths[0]
    if os.path.getmtime(best_polar) > task_start:
        polar_path_found = best_polar
        polar_exists = True
        try:
            with open(polar_path_found, 'r', errors='replace') as f:
                polar_content = f.read()
        except Exception:
            pass

# 3. Read report
report_exists = os.path.isfile(report_path)
report_content = ''
if report_exists:
    try:
        with open(report_path, 'r', errors='replace') as f:
            report_content = f.read()
    except Exception:
        pass

result = {
    'task_start': task_start,
    'model_exists': model_exists,
    'model_mtime': model_mtime,
    'model_content': model_content,
    'polar_exists': polar_exists,
    'polar_path': polar_path_found,
    'polar_content': polar_content,
    'report_exists': report_exists,
    'report_content': report_content
}

with open('/tmp/openvsp_stability_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Model: exists={model_exists}, mtime={model_mtime}")
print(f"Polar: exists={polar_exists}, path={polar_path_found}")
print(f"Report: exists={report_exists}, length={len(report_content)}")
PYEOF

echo "=== Export complete ==="