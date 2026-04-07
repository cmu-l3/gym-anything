#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting result for openvsp_winglet_addition ==="

# Take final screenshot before killing the application
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks and flush buffers
kill_openvsp
sleep 1

# Read the start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Use Python to accurately export file metadata and content
python3 << PYEOF
import json
import os

out_path = '/home/ga/Documents/OpenVSP/eCRM001_winglet.vsp3'
orig_path = '/home/ga/Documents/OpenVSP/eCRM-001_wing_tail.vsp3'

exists = os.path.isfile(out_path)
mtime = int(os.path.getmtime(out_path)) if exists else 0
size = os.path.getsize(out_path) if exists else 0

content = ''
if exists:
    with open(out_path, 'r', errors='replace') as f:
        content = f.read()

# Count initial Dihedral tags to verify the agent actually added a section
orig_dihedrals = 0
if os.path.isfile(orig_path):
    with open(orig_path, 'r', errors='replace') as f:
        orig_content = f.read()
        orig_dihedrals = orig_content.count('<Dihedral ')

result = {
    'file_exists': exists,
    'mtime': mtime,
    'size': size,
    'content': content,
    'task_start': $TASK_START,
    'orig_dihedrals': orig_dihedrals
}

with open('/tmp/openvsp_winglet_result.json', 'w') as f:
    json.dump(result, f)

print(f"Exported result: exists={exists}, size={size}, orig_dihedrals={orig_dihedrals}")
PYEOF

echo "=== Export complete ==="