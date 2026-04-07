#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/seller_commissions.xlsx"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json
import os

target_file = "/home/ga/Documents/seller_commissions.xlsx"
result = {
    "file_exists": False,
    "file_modified": False,
    "mtime": 0,
    "error": None
}

if os.path.exists(target_file):
    result["file_exists"] = True
    result["mtime"] = os.path.getmtime(target_file)
    
    # Check if modified during the task
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = float(f.read().strip())
            result["file_modified"] = result["mtime"] > start_time
    except Exception:
        pass
else:
    result["error"] = "File not found"

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="