#!/bin/bash
echo "=== Exporting Workspace and Code Remediation Result ==="

source /workspace/scripts/task_utils.sh

# Focus VS Code and attempt to save all open files
WID=$(get_vscode_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 0.5
    DISPLAY=:1 xdotool key --delay 100 ctrl+k s 2>/dev/null || true
    sleep 1
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

WORKSPACE_DIR="/home/ga/workspace/starlette_project"
RESULT_FILE="/tmp/workspace_result.json"

# Remove any stale result file
rm -f "$RESULT_FILE"

# Extract configuration and code states into a single JSON dict using Python
python3 << PYEXPORT
import json
import os
import subprocess
import time

workspace = "$WORKSPACE_DIR"
result = {
    "timestamp": int(time.time()),
    "task_start_time": 0,
    "files": {},
    "lint_results": {}
}

# Get task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        result["task_start_time"] = int(f.read().strip())
except Exception:
    pass

# Read .vscode JSON files
vscode_dir = os.path.join(workspace, ".vscode")
vscode_files = ["settings.json", "extensions.json", "launch.json", "tasks.json"]

for f in vscode_files:
    path = os.path.join(vscode_dir, f)
    file_data = {"exists": False, "is_valid_json": False, "content": None, "mtime": 0}
    if os.path.exists(path):
        file_data["exists"] = True
        file_data["mtime"] = int(os.path.getmtime(path))
        try:
            with open(path, "r", encoding="utf-8") as file:
                file_data["content"] = json.load(file)
                file_data["is_valid_json"] = True
        except Exception:
            pass
    result["files"][f] = file_data

# Read Source Python files
src_files = ["starlette/applications.py", "starlette/routing.py"]
for f in src_files:
    path = os.path.join(workspace, f)
    file_data = {"exists": False, "lines": 0, "mtime": 0, "content": ""}
    if os.path.exists(path):
        file_data["exists"] = True
        file_data["mtime"] = int(os.path.getmtime(path))
        try:
            with open(path, "r", encoding="utf-8") as file:
                content = file.read()
                file_data["content"] = content
                file_data["lines"] = len(content.splitlines())
        except Exception:
            pass
    result["files"][f] = file_data

# Run Black format check on applications.py
app_path = os.path.join(workspace, "starlette/applications.py")
if os.path.exists(app_path):
    cp = subprocess.run(["black", "--check", app_path], capture_output=True, text=True)
    result["lint_results"]["black_exit_code"] = cp.returncode
    result["lint_results"]["black_output"] = cp.stderr + cp.stdout
else:
    result["lint_results"]["black_exit_code"] = -1

# Run Flake8 check on routing.py
rout_path = os.path.join(workspace, "starlette/routing.py")
if os.path.exists(rout_path):
    cp = subprocess.run(["flake8", rout_path], capture_output=True, text=True)
    result["lint_results"]["flake8_exit_code"] = cp.returncode
    result["lint_results"]["flake8_output"] = cp.stdout + cp.stderr
else:
    result["lint_results"]["flake8_exit_code"] = -1

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported verification data to $RESULT_FILE")
PYEXPORT

echo "=== Export Complete ==="