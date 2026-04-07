#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Planar Slice Area Distribution result ==="

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Safely kill OpenVSP to flush any unwritten file handles
kill_openvsp

# Use Python to safely parse filesystem state and build JSON result
python3 << 'EOF'
import json
import os
import glob

# Read task start time
start_time = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    pass

# Search for the generated slice file (.slc or files with slice in name)
search_dirs = [
    '/home/ga/Documents/OpenVSP/exports',
    '/home/ga/Documents/OpenVSP',
    '/home/ga/Desktop'
]

slice_file_path = None
# Look for files modified AFTER task start
for d in search_dirs:
    for root, dirs, files in os.walk(d):
        for file in files:
            if file.endswith('.slc') or 'slice' in file.lower() or 'area_ruling' in file.lower():
                # Ignore the report itself
                if file == 'area_ruling_report.txt':
                    continue
                
                full_path = os.path.join(root, file)
                try:
                    mtime = os.path.getmtime(full_path)
                    if mtime >= start_time - 5:
                        slice_file_path = full_path
                        break
                except Exception:
                    pass
        if slice_file_path:
            break
    if slice_file_path:
        break

slice_rows = 0
slice_content_preview = ""
if slice_file_path:
    try:
        with open(slice_file_path, 'r', errors='replace') as f:
            lines = f.readlines()
            # Count lines that contain numeric data (likely tabular rows)
            slice_rows = len([l for l in lines if any(c.isdigit() for c in l)])
            slice_content_preview = "".join(lines[:50])
    except Exception:
        pass

# Check report file
report_path = '/home/ga/Desktop/area_ruling_report.txt'
report_exists = os.path.exists(report_path)
report_content = ""
if report_exists:
    try:
        with open(report_path, 'r', errors='replace') as f:
            report_content = f.read()
    except Exception:
        pass

# Assemble result
result = {
    "task_start_time": start_time,
    "slice_file_found": slice_file_path is not None,
    "slice_file_path": slice_file_path or "",
    "slice_data_rows": slice_rows,
    "slice_content_preview": slice_content_preview,
    "report_exists": report_exists,
    "report_content": report_content
}

# Write out to temp JSON, then move (prevents bash escape issues)
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result JSON written:"
cat /tmp/task_result.json
echo "=== Export complete ==="