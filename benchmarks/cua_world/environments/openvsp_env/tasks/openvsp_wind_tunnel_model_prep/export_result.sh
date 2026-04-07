#!/bin/bash
# Export script for openvsp_wind_tunnel_model_prep
set -e

echo "=== Exporting task results ==="

# Source shared OpenVSP utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot showing end state
take_screenshot /tmp/task_final.png

# Kill OpenVSP to release file locks on the saved vsp3/stl files
kill_openvsp

# Use Python to safely package file content and metadata into JSON
python3 << 'PYEOF'
import json
import os

exports_dir = '/home/ga/Documents/OpenVSP/exports'
vsp3_path = os.path.join(exports_dir, 'wt_model.vsp3')
stl_path = os.path.join(exports_dir, 'wt_model.stl')

vsp3_exists = os.path.isfile(vsp3_path)
stl_exists = os.path.isfile(stl_path)

vsp3_content = ""
vsp3_size = 0
vsp3_mtime = 0
if vsp3_exists:
    vsp3_size = os.path.getsize(vsp3_path)
    vsp3_mtime = int(os.path.getmtime(vsp3_path))
    with open(vsp3_path, 'r', errors='replace') as f:
        vsp3_content = f.read()

stl_size = 0
stl_mtime = 0
stl_first_bytes = ""
if stl_exists:
    stl_size = os.path.getsize(stl_path)
    stl_mtime = int(os.path.getmtime(stl_path))
    if stl_size > 0:
        with open(stl_path, 'rb') as f:
            stl_first_bytes = f.read(256).hex()

task_start = 0
if os.path.isfile('/tmp/task_start_time.txt'):
    with open('/tmp/task_start_time.txt', 'r') as f:
        try:
            task_start = int(f.read().strip())
        except ValueError:
            pass

result = {
    'task_start': task_start,
    'vsp3_exists': vsp3_exists,
    'vsp3_size': vsp3_size,
    'vsp3_mtime': vsp3_mtime,
    'vsp3_content': vsp3_content,
    'stl_exists': stl_exists,
    'stl_size': stl_size,
    'stl_mtime': stl_mtime,
    'stl_first_bytes': stl_first_bytes
}

temp_json = '/tmp/result.temp.json'
with open(temp_json, 'w') as f:
    json.dump(result, f)

# Move to final location safely
os.rename(temp_json, '/tmp/task_result.json')
os.chmod('/tmp/task_result.json', 0o666)

print(f"Exported: VSP3 Exists={vsp3_exists} ({vsp3_size} bytes), STL Exists={stl_exists} ({stl_size} bytes)")
PYEOF

echo "=== Export complete ==="