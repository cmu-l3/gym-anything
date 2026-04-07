#!/bin/bash
# Export script for openvsp_cfd_mesh_refinement task
# Records the resulting project file and the exported mesh metrics

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_cfd_mesh_result.json"

echo "=== Exporting result for openvsp_cfd_mesh_refinement ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Kill OpenVSP to release file locks and flush saves
kill_openvsp

# Use Python to gather all required file evidence and output JSON
python3 << PYEOF
import json
import os

models_dir = '/home/ga/Documents/OpenVSP'
exports_dir = '/home/ga/Documents/OpenVSP/exports'

vsp3_path = os.path.join(models_dir, 'eCRM001_mesh_setup.vsp3')
tri_path = os.path.join(exports_dir, 'eCRM001_refined.tri')
task_start = int($TASK_START)

result = {
    'task_start': task_start,
    'vsp3_exists': False,
    'vsp3_size': 0,
    'vsp3_mtime': 0,
    'vsp3_created_during_task': False,
    'vsp3_content': '',
    
    'tri_exists': False,
    'tri_size': 0,
    'tri_mtime': 0,
    'tri_created_during_task': False,
    'tri_header': '',
    'tri_count': 0
}

# Process VSP3 File
if os.path.isfile(vsp3_path):
    result['vsp3_exists'] = True
    result['vsp3_size'] = os.path.getsize(vsp3_path)
    result['vsp3_mtime'] = int(os.path.getmtime(vsp3_path))
    result['vsp3_created_during_task'] = result['vsp3_mtime'] >= task_start
    try:
        with open(vsp3_path, 'r', errors='replace') as f:
            result['vsp3_content'] = f.read()
    except Exception:
        pass

# Process Cart3D .tri File
if os.path.isfile(tri_path):
    result['tri_exists'] = True
    result['tri_size'] = os.path.getsize(tri_path)
    result['tri_mtime'] = int(os.path.getmtime(tri_path))
    result['tri_created_during_task'] = result['tri_mtime'] >= task_start
    try:
        with open(tri_path, 'r', errors='replace') as f:
            # First line of Cart3D .tri is usually "<nNodes> <nTris>"
            header = f.readline().strip()
            result['tri_header'] = header
            parts = header.split()
            if len(parts) >= 2:
                result['tri_count'] = int(parts[1])
            else:
                # Fallback: line count approx nodes + tris
                pass
    except Exception:
        pass

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported JSON: VSP3 Exists={result['vsp3_exists']}, TRI Exists={result['tri_exists']}, Tri Count={result['tri_count']}")
PYEOF

echo "=== Export complete ==="