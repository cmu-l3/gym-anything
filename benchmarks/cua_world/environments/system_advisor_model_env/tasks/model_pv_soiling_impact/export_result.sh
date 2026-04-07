#!/bin/bash
echo "=== Exporting soiling analysis results ==="

# Record final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gather file info using Python to parse the JSON robustly
python3 << 'PYEOF'
import json
import os
import sys
import glob

output_file = "/tmp/task_result.json"
result_file = "/home/ga/Documents/SAM_Projects/soiling_analysis.json"
task_start = 0

if os.path.exists("/tmp/task_start_time.txt"):
    try:
        with open("/tmp/task_start_time.txt") as f:
            task_start = int(f.read().strip())
    except:
        pass

output = {
    "file_exists": os.path.exists(result_file),
    "file_size_bytes": os.path.getsize(result_file) if os.path.exists(result_file) else 0,
    "file_mtime": int(os.path.getmtime(result_file)) if os.path.exists(result_file) else 0,
    "task_start_time": task_start,
    "file_created_during_task": False,
    "valid_json": False,
    "data": {},
    "python_scripts_found": []
}

if output["file_exists"]:
    output["file_created_during_task"] = output["file_mtime"] > task_start
    try:
        with open(result_file, "r") as f:
            output["data"] = json.load(f)
        output["valid_json"] = True
    except Exception as e:
        output["parse_error"] = str(e)

# Find any python scripts created by the agent
py_files = []
for d in ["/home/ga", "/home/ga/Documents", "/home/ga/Documents/SAM_Projects"]:
    if os.path.isdir(d):
        for f in glob.glob(os.path.join(d, "*.py")):
            if os.path.getmtime(f) > task_start:
                py_files.append(f)
output["python_scripts_found"] = py_files

with open(output_file, "w") as f:
    json.dump(output, f, indent=2)

print("Exported JSON metadata.")
PYEOF

cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="