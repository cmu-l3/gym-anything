#!/bin/bash
echo "=== Exporting openvsp_catapult_hook_cg_alignment ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks
kill_openvsp

# Read output files
python3 << 'PYEOF'
import json
import os

models_dir = '/home/ga/Documents/OpenVSP'

model_file = os.path.join(models_dir, 'uav_launch_ready.vsp3')
massprops_file = os.path.join(models_dir, 'tactical_uav_MassProps.txt')

result = {
    'model_exists': os.path.exists(model_file),
    'massprops_exists': os.path.exists(massprops_file),
    'model_content': '',
    'massprops_content': '',
    'mtime_model': 0,
    'mtime_massprops': 0
}

if result['model_exists']:
    with open(model_file, 'r', errors='replace') as f:
        result['model_content'] = f.read()
    result['mtime_model'] = int(os.path.getmtime(model_file))

if result['massprops_exists']:
    with open(massprops_file, 'r', errors='replace') as f:
        result['massprops_content'] = f.read()
    result['mtime_massprops'] = int(os.path.getmtime(massprops_file))

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

echo "=== Export complete ==="