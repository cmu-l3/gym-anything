#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting result ==="

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Kill OpenVSP to ensure file buffers are flushed and files are fully saved
kill_openvsp

# Parse the resulting file metadata and content
python3 << 'PYEOF'
import json
import os

# Fetch start time
start_time = 0
try:
    with open('/tmp/task_start_time', 'r') as f:
        start_time = int(f.read().strip())
except Exception:
    pass

output_path = '/home/ga/Documents/OpenVSP/exports/eCRM001_structural.vsp3'
exists = os.path.isfile(output_path)
mtime = int(os.path.getmtime(output_path)) if exists else 0
size = os.path.getsize(output_path) if exists else 0

content = ""
if exists:
    with open(output_path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'task_start_time': start_time,
    'file_exists': exists,
    'file_mtime': mtime,
    'file_size': size,
    'file_content': content
}

# Write results cleanly to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

echo "Result metadata and payload saved to /tmp/task_result.json"
echo "=== Export complete ==="