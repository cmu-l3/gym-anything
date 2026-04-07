#!/bin/bash
# Export script for openvsp_twin_boom_uav task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting result for openvsp_twin_boom_uav ==="

# Take final screenshot before killing OpenVSP
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release any file locks
kill_openvsp

# Read the saved .vsp3 file into JSON for the verifier
python3 << 'PYEOF'
import json
import os

model_path = '/home/ga/Documents/OpenVSP/twin_boom_uav.vsp3'
exists = os.path.isfile(model_path)
size = os.path.getsize(model_path) if exists else 0
content = ''

if exists:
    with open(model_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_size': size,
    'file_content': content,
    'mtime': int(os.path.getmtime(model_path)) if exists else 0,
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

print(f"Exported result: file_exists={exists}, size={size} bytes")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="