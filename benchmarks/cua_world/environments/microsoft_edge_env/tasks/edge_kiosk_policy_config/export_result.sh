#!/bin/bash
# Export script for Edge Kiosk Policy Config task
set -e

echo "=== Exporting Edge Kiosk Policy Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
POLICY_DIR="/etc/microsoft-edge/policies/managed"
REPORT_PATH="/home/ga/Desktop/kiosk_deploy_report.txt"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Collect Policy Files
# We need to read the JSON content. Since we might have multiple files,
# we'll use Python to aggregate them.
echo "Reading policy files..."

python3 << PYEOF
import json
import os
import glob
import time

policy_dir = "$POLICY_DIR"
report_path = "$REPORT_PATH"
task_start = $TASK_START

result = {
    "policy_files_found": [],
    "aggregated_policies": {},
    "report_exists": False,
    "report_content": "",
    "report_mtime": 0,
    "file_timestamps_valid": False,
    "timestamp": time.time()
}

# 1. Parse Policy Files
if os.path.exists(policy_dir):
    json_files = glob.glob(os.path.join(policy_dir, "*.json"))
    valid_timestamps = True
    
    for f in json_files:
        try:
            stat = os.stat(f)
            # Check if file was modified after task start
            if stat.st_mtime < task_start:
                valid_timestamps = False
            
            with open(f, 'r') as jf:
                data = json.load(jf)
                # Merge into aggregated policies
                result["aggregated_policies"].update(data)
                
            result["policy_files_found"].append({
                "path": f,
                "valid_json": True,
                "mtime": stat.st_mtime
            })
        except Exception as e:
            result["policy_files_found"].append({
                "path": f,
                "valid_json": False,
                "error": str(e)
            })
            
    if json_files and valid_timestamps:
        result["file_timestamps_valid"] = True
    elif not json_files:
        result["file_timestamps_valid"] = False # No files found

# 2. Check Report
if os.path.exists(report_path):
    result["report_exists"] = True
    stat = os.stat(report_path)
    result["report_mtime"] = stat.st_mtime
    try:
        with open(report_path, 'r', errors='ignore') as rf:
            result["report_content"] = rf.read()
    except:
        result["report_content"] = "[Error reading report]"

# 3. Write result
with open("/tmp/task_result.json", "w") as out:
    json.dump(result, out, indent=2)

PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="