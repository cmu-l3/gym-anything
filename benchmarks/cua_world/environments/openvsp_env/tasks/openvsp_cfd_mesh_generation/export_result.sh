#!/bin/bash
# Export script for openvsp_cfd_mesh_generation task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_cfd_mesh_result.json"

echo "=== Exporting result for openvsp_cfd_mesh_generation ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks
kill_openvsp

# Extract data using Python
python3 << 'PYEOF'
import json
import os
import struct

exports_dir = '/home/ga/Documents/OpenVSP/exports'
desktop_dir = '/home/ga/Desktop'

stl_path = os.path.join(exports_dir, 'eCRM001_cfd_mesh.stl')
gmsh_path = os.path.join(exports_dir, 'eCRM001_cfd_mesh.msh')
report_path = os.path.join(desktop_dir, 'cfd_mesh_report.txt')

task_start_timestamp = 0
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        task_start_timestamp = int(f.read().strip())
except Exception:
    pass

def get_stl_info(path):
    info = {'exists': False, 'size': 0, 'mtime': 0, 'triangles': 0, 'is_ascii': False}
    if not os.path.isfile(path):
        return info
    
    info['exists'] = True
    info['size'] = os.path.getsize(path)
    info['mtime'] = int(os.path.getmtime(path))
    
    try:
        with open(path, 'rb') as f:
            header = f.read(80)
            if header.startswith(b'solid'):
                info['is_ascii'] = True
                f.seek(0)
                # Count 'facet normal' for ASCII
                content = f.read().decode('ascii', errors='ignore')
                info['triangles'] = content.count('facet normal')
            else:
                # Binary STL has uint32 triangle count at byte 80
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    info['triangles'] = struct.unpack('<I', count_bytes)[0]
    except Exception:
        pass
    return info

def get_gmsh_info(path):
    info = {'exists': False, 'size': 0, 'mtime': 0, 'has_nodes': False, 'has_elements': False}
    if not os.path.isfile(path):
        return info
    
    info['exists'] = True
    info['size'] = os.path.getsize(path)
    info['mtime'] = int(os.path.getmtime(path))
    
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read(5000) # Only read first part to check headers
            info['has_nodes'] = '$Nodes' in content
            info['has_elements'] = '$Elements' in content
    except Exception:
        pass
    return info

stl_info = get_stl_info(stl_path)
gmsh_info = get_gmsh_info(gmsh_path)

report_content = ""
report_exists = os.path.isfile(report_path)
if report_exists:
    try:
        with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
    except Exception:
        pass

result = {
    'task_start_time': task_start_timestamp,
    'stl': stl_info,
    'gmsh': gmsh_info,
    'report': {
        'exists': report_exists,
        'content': report_content
    }
}

with open('/tmp/openvsp_cfd_mesh_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"STL: exists={stl_info['exists']}, size={stl_info['size']}, tris={stl_info['triangles']}")
print(f"GMSH: exists={gmsh_info['exists']}, size={gmsh_info['size']}, nodes_header={gmsh_info['has_nodes']}")
print(f"Report: exists={report_exists}, len={len(report_content)}")

PYEOF

echo "=== Export complete ==="