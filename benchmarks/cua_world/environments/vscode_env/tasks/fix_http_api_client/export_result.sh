#!/bin/bash
set -e
echo "=== Exporting Fix HTTP API Client Task Result ==="

WORKSPACE_DIR="/home/ga/workspace/api_client"
RESULT_FILE="/tmp/api_client_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Attempt to save open files in VSCode (Ctrl+K, S to save all)
export DISPLAY=:1
su - ga -c "xdotool key ctrl+k s" 2>/dev/null || true
sleep 1

# Run pytest to capture actual test output (for verifier or debugging context)
echo "Running pytest..."
cd "$WORKSPACE_DIR"
su - ga -c "cd $WORKSPACE_DIR && pytest tests/test_client.py --tb=short -q > /tmp/pytest_out.txt 2>&1" || true

# Python script to bundle files and analyze timestamps
python3 << PYEXPORT
import json
import os
import stat

workspace = "$WORKSPACE_DIR"
task_start = int("$TASK_START")

files_to_export = [
    "client/url_builder.py",
    "client/retry.py",
    "client/http_client.py",
    "client/auth.py",
    "client/pagination.py",
]

result = {
    "files": {},
    "file_modified_during_task": False,
    "pytest_output": ""
}

# Check if any file was modified
for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    try:
        mtime = int(os.stat(full_path).st_mtime)
        if mtime > task_start:
            result["file_modified_during_task"] = True
            
        with open(full_path, "r", encoding="utf-8") as f:
            result["files"][rel_path] = f.read()
    except Exception as e:
        result["files"][rel_path] = f"ERROR: {e}"

# Load pytest output
try:
    with open("/tmp/pytest_out.txt", "r") as f:
        result["pytest_output"] = f.read()
except Exception:
    pass

# Write to tmp location
with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)
PYEXPORT

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result JSON saved to $RESULT_FILE"
echo "=== Export Complete ==="