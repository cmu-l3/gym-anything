#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting result for openvsp_component_buildup_sets ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to ensure files are flushed and handles released
kill_openvsp

# Retrieve task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Use Python to gather file metadata and content, preventing escaping issues
python3 << PYEOF
import json
import os

path = '/home/ga/Documents/OpenVSP/exports/eCRM-001_sets.vsp3'
exists = os.path.isfile(path)
mtime = int(os.path.getmtime(path)) if exists else 0
size = os.path.getsize(path) if exists else 0

# Verify file was created/modified during the task window
file_modified = True if (exists and mtime >= $TASK_START) else False

content = ""
if exists:
    with open(path, 'r', errors='replace') as f:
        content = f.read()

result = {
    'file_exists': exists,
    'file_modified': file_modified,
    'mtime': mtime,
    'size': size,
    'content': content
}

with open('/tmp/openvsp_sets_result.json', 'w') as f:
    json.dump(result, f)

print(f"Result written: file_exists={exists}, file_modified={file_modified}, size={size}")
PYEOF

echo "=== Export complete ==="