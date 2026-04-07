#!/bin/bash
# Export script for openvsp_wave_drag_area_ruling task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/wave_drag_result.json"

echo "=== Exporting result for openvsp_wave_drag_area_ruling ==="

# Take final screenshot before killing the app
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP so file handles are released
kill_openvsp

# Extract data to JSON for the verifier
python3 << PYEOF
import json, os, hashlib

desktop = '/home/ga/Desktop'
models_dir = '/home/ga/Documents/OpenVSP'
report_path = os.path.join(desktop, 'wave_drag_report.txt')
model_path = os.path.join(models_dir, 'eCRM-001_wave_drag.vsp3')

# 1. Read Report
report_exists = os.path.isfile(report_path)
report_content = ''
report_mtime = 0
if report_exists:
    report_mtime = int(os.path.getmtime(report_path))
    try:
        with open(report_path, 'r', errors='replace') as f:
            report_content = f.read()
    except Exception as e:
        report_content = f"Error reading file: {e}"

# 2. Read Saved Model
model_exists = os.path.isfile(model_path)
model_content = ''
model_hash = ''
model_mtime = 0
if model_exists:
    model_mtime = int(os.path.getmtime(model_path))
    try:
        with open(model_path, 'r', errors='replace') as f:
            model_content = f.read()
        
        # Calculate hash to compare with original
        hasher = hashlib.md5()
        with open(model_path, 'rb') as f:
            buf = f.read()
            hasher.update(buf)
        model_hash = hasher.hexdigest()
    except Exception as e:
        model_content = ""

# 3. Read Original Model Hash
orig_hash_path = '/tmp/original_model_hash.txt'
orig_hash = ''
if os.path.isfile(orig_hash_path):
    with open(orig_hash_path, 'r') as f:
        orig_hash = f.read().strip()

# 4. Get task start time
task_start = 0
start_time_path = '/tmp/task_start_timestamp'
if os.path.isfile(start_time_path):
    with open(start_time_path, 'r') as f:
        task_start = int(f.read().strip() or 0)

result = {
    'task_start_time': task_start,
    'report_exists': report_exists,
    'report_mtime': report_mtime,
    'report_content': report_content,
    'model_exists': model_exists,
    'model_mtime': model_mtime,
    'model_hash': model_hash,
    'original_model_hash': orig_hash,
    'model_content': model_content[:10000] # First 10KB to keep JSON manageable but enough to check XML structure
}

# Write results to temp JSON then move
temp_path = '/tmp/temp_wave_drag.json'
with open(temp_path, 'w') as f:
    json.dump(result, f, indent=2)

os.system(f"mv {temp_path} {RESULT_FILE}")
os.system(f"chmod 666 {RESULT_FILE}")

print(f"Exported data: Report Exists={report_exists}, Model Exists={model_exists}")
PYEOF

echo "=== Export complete ==="