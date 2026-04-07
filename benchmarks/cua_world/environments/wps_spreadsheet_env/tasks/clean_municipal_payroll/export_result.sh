#!/bin/bash
echo "=== Exporting task result ==="

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json
import os

result = {
    "file_exists": False,
    "file_size": 0,
    "file_mtime": 0,
    "error": None
}

target_file = "/home/ga/Documents/chicago_employees.xlsx"

if os.path.exists(target_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(target_file)
    result["file_mtime"] = os.path.getmtime(target_file)
else:
    result["error"] = "File not found"

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="