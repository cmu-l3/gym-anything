#!/bin/bash
set -e

echo "=== Exporting Robotic Arm Task Result ==="

WORKSPACE_DIR="/home/ga/workspace/robotic_arm_sim"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus VS Code and save all files
if type focus_vscode_window &>/dev/null; then
    focus_vscode_window 2>/dev/null || true
fi
sudo -u ga DISPLAY=:1 xdotool key --delay 200 ctrl+shift+s 2>/dev/null || true
sudo -u ga DISPLAY=:1 xdotool key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Run tests and capture output
cd "$WORKSPACE_DIR"
sudo -u ga python3 -m pytest tests/ -v > /tmp/pytest_output.log 2>&1 || true

# Export all data to JSON
python3 << 'PYEXPORT'
import json, os, time

workspace = "/home/ga/workspace/robotic_arm_sim"
files_to_export = [
    "controller/pid.py",
    "sensors/filter.py",
    "kinematics/inverse.py",
    "controller/trajectory_planner.py",
    "safety/limits.py"
]

result = {}
start_time = 0
if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt") as f:
        start_time = int(f.read().strip())

for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    file_data = {"content": "", "modified": False}
    try:
        with open(full_path, "r", encoding="utf-8") as f:
            file_data["content"] = f.read()
        mtime = os.path.getmtime(full_path)
        if mtime > start_time:
            file_data["modified"] = True
    except Exception as e:
        file_data["content"] = f"ERROR: {e}"
    result[rel_path] = file_data

try:
    with open("/tmp/pytest_output.log", "r") as f:
        result["pytest_log"] = f.read()
except:
    result["pytest_log"] = ""

with open("/tmp/task_result.json", "w") as out:
    json.dump(result, out, indent=2)
PYEXPORT

chmod 666 /tmp/task_result.json
echo "=== Export Complete ==="