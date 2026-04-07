#!/bin/bash
# Export script for openvsp_three_view_drawing_export task
# Captures file existence, sizes, and hashes of the exported SVGs

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_three_view_drawing_export_result.json"

echo "=== Exporting result for openvsp_three_view_drawing_export ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file handles
kill_openvsp

python3 << PYEOF
import json
import os
import hashlib

exports_dir = '/home/ga/Documents/OpenVSP/exports'
task_start = int('$TASK_START')
task_end = int('$TASK_END')

target_files = {
    'top': os.path.join(exports_dir, 'eCRM001_top.svg'),
    'front': os.path.join(exports_dir, 'eCRM001_front.svg'),
    'side': os.path.join(exports_dir, 'eCRM001_side.svg')
}

result = {
    'task_start': task_start,
    'task_end': task_end,
    'files': {}
}

for key, path in target_files.items():
    exists = os.path.isfile(path)
    size = os.path.getsize(path) if exists else 0
    mtime = int(os.path.getmtime(path)) if exists else 0
    created_during_task = (mtime >= task_start) if exists else False
    
    file_hash = ''
    content_snippet = ''
    
    if exists and size > 0:
        with open(path, 'rb') as f:
            content = f.read()
            file_hash = hashlib.sha256(content).hexdigest()
            # Try to grab the first 256 characters for basic validation
            try:
                content_snippet = content[:256].decode('utf-8', errors='replace')
            except Exception:
                pass

    result['files'][key] = {
        'exists': exists,
        'size': size,
        'mtime': mtime,
        'created_during_task': created_during_task,
        'hash': file_hash,
        'content_snippet': content_snippet
    }
    print(f"File {key}: exists={exists}, size={size}, created_during_task={created_during_task}")

# Write to temp file then move to prevent permission issues
temp_out = '/tmp/export_temp.json'
with open(temp_out, 'w') as f:
    json.dump(result, f, indent=2)

os.system(f"mv {temp_out} {result_file}")
os.system(f"chmod 666 {result_file}")

print(f"Result written to {result_file}")
PYEOF

echo "=== Export complete ==="