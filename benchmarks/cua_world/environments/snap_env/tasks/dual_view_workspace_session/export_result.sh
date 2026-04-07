#!/bin/bash
echo "=== Exporting dual_view_workspace_session result ==="

source /workspace/utils/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'has_vector_node': False,
    'snap_session_found': False,
    'snap_created_after_start': False,
    'has_view1': False,
    'has_view2': False,
    'png_found': False,
    'png_created_after_start': False,
    'png_size': 0
}

search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga', '/tmp']

# 1. Check Product DIMAP
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim') and 'snap_data' not in root:
                    dim_files.append(os.path.join(root, f))

for dim_file in dim_files:
    mtime = int(os.path.getmtime(dim_file))
    if mtime > task_start:
        result['dim_created_after_start'] = True
    result['dim_found'] = True
    try:
        tree = ET.parse(dim_file)
        root = tree.getroot()
        for vnode in root.iter('Vector_Data_Node'):
            result['has_vector_node'] = True
            break
    except Exception:
        pass

# 2. Check Session SNAP
snap_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.snap'):
                    snap_files.append(os.path.join(root, f))

for snap_file in snap_files:
    mtime = int(os.path.getmtime(snap_file))
    if mtime > task_start:
        result['snap_created_after_start'] = True
    result['snap_session_found'] = True
    try:
        with open(snap_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            if 'band_1' in content and 'band_2' in content and 'band_3' in content:
                result['has_view1'] = True
            if 'band_2' in content and 'band_3' in content and 'band_4' in content:
                result['has_view2'] = True
    except Exception:
        pass

# 3. Check PNG Export
png_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.png') and 'screenshot' not in f.lower():
                    png_files.append(os.path.join(root, f))

for png_file in png_files:
    mtime = int(os.path.getmtime(png_file))
    size = os.path.getsize(png_file)
    if mtime > task_start:
        result['png_created_after_start'] = True
    result['png_found'] = True
    if size > result['png_size']:
        result['png_size'] = size

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="