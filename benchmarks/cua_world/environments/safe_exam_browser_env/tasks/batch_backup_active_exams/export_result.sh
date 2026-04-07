#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting batch_backup_active_exams results ==="

# Capture final visual state
take_screenshot /tmp/final_screenshot.png

# Export data via Python script
python3 << 'PYEOF'
import json
import os
import time

backup_dir = "/home/ga/Documents/ExamBackups"
start_time_path = '/tmp/task_start_time.txt'
start_time = float(open(start_time_path).read().strip()) if os.path.exists(start_time_path) else 0

# Read Ground Truth populated during setup
gt = {"active": [], "inactive": []}
try:
    with open('/tmp/ground_truth_exams.json', 'r') as f:
        gt = json.load(f)
except Exception:
    pass

# Check output directory and files
files_found = []
dir_exists = os.path.isdir(backup_dir)

if dir_exists:
    for fname in os.listdir(backup_dir):
        fpath = os.path.join(backup_dir, fname)
        if os.path.isfile(fpath):
            stat = os.stat(fpath)
            files_found.append({
                "filename": fname,
                "size": stat.st_size,
                "mtime": stat.st_mtime,
                "created_during_task": stat.st_mtime > start_time
            })

result = {
    "timestamp": time.time(),
    "task_start_time": start_time,
    "dir_exists": dir_exists,
    "files_found": files_found,
    "ground_truth": gt
}

with open('/tmp/batch_backup_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="