#!/bin/bash
echo "=== Exporting optimize_sky_annulus result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/task_final.png

# Package outputs safely via Python
python3 << 'EOF'
import os
import json

csv_path = "/home/ga/AstroImages/measurements/annulus_test.csv"
txt_path = "/home/ga/AstroImages/measurements/conclusion.txt"
start_time_file = "/tmp/task_start_time.txt"

task_start = 0
if os.path.exists(start_time_file):
    with open(start_time_file, 'r') as f:
        try:
            task_start = float(f.read().strip())
        except ValueError:
            pass

csv_mtime = os.path.getmtime(csv_path) if os.path.exists(csv_path) else 0
txt_mtime = os.path.getmtime(txt_path) if os.path.exists(txt_path) else 0

# Limit read size to prevent OOM
def read_safe(path, limit=10000):
    if not os.path.exists(path):
        return ""
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        return f.read()[:limit]

res = {
    "csv_exists": os.path.exists(csv_path),
    "txt_exists": os.path.exists(txt_path),
    "csv_content": read_safe(csv_path),
    "txt_content": read_safe(txt_path),
    "csv_created_during_task": csv_mtime >= task_start if task_start else True,
    "txt_created_during_task": txt_mtime >= task_start if task_start else True
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(res, f)
EOF

chmod 666 /tmp/task_result.json
echo "=== Export complete ==="