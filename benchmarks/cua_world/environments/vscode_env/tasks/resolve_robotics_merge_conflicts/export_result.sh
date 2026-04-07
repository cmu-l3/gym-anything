#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Resolve Robotics Merge Conflicts Result ==="

WORKSPACE_DIR="/home/ga/workspace/robocontrol"
RESULT_FILE="/tmp/merge_task_result.json"

# Best-effort: save all open files in VSCode so we capture the current state
WID=$(wmctrl -l | grep -i "Visual Studio Code" | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null
    sleep 0.5
    # Ctrl+K, S saves all files in VS Code
    su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+k s" 2>/dev/null || true
    sleep 2
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Collect Git State
cd "$WORKSPACE_DIR"
GIT_STATUS=$(sudo -u ga git status --porcelain 2>/dev/null || echo "ERROR")
GIT_LOG=$(sudo -u ga git log -1 --format="%H|%P|%s|%at" 2>/dev/null || echo "ERROR")

# Create JSON export script
python3 << PYEXPORT
import json
import os

workspace = "$WORKSPACE_DIR"
git_status = """$GIT_STATUS"""
git_log = """$GIT_LOG"""

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start_time = int(f.read().strip())
except:
    task_start_time = 0

files_to_export = [
    "config/robot_params.yaml",
    "src/robot_controller.py",
    "src/utils/transforms.py",
    "tests/test_controller.py",
    "README.md"
]

result = {
    "task_start_time": task_start_time,
    "git_status": git_status.strip(),
    "git_log": git_log.strip(),
    "files": {}
}

for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    try:
        with open(full_path, "r", encoding="utf-8") as f:
            result["files"][rel_path] = f.read()
    except Exception as e:
        result["files"][rel_path] = ""

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files and git state to {RESULT_FILE}")
PYEXPORT

echo "=== Export Complete ==="