#!/bin/bash
echo "=== Exporting Fix Scientific Computing Library Result ==="

source /workspace/scripts/task_utils.sh

WORKSPACE_DIR="/home/ga/workspace/numlib"
RESULT_FILE="/tmp/scientific_library_result.json"
TEST_REPORT="/tmp/test_report.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove stale files
rm -f "$RESULT_FILE"
rm -f "$TEST_REPORT"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run the test suite within the container to generate the report
echo "Running test suite..."
sudo -u ga python3 "$WORKSPACE_DIR/run_tests.py" --json "$TEST_REPORT" || true

# Collect test report, file timestamps, and source code for verification
python3 << PYEXPORT
import json
import os

workspace = "$WORKSPACE_DIR"
task_start = 0
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    pass

files_to_export = [
    "numlib/integration.py",
    "numlib/ode_solver.py",
    "numlib/linear_algebra.py",
    "numlib/interpolation.py",
    "numlib/root_finder.py"
]

result = {
    "test_report": {},
    "files": {},
    "task_start_time": task_start
}

# Read test report
try:
    if os.path.exists("$TEST_REPORT"):
        with open("$TEST_REPORT", "r") as f:
            result["test_report"] = json.load(f)
except Exception as e:
    print(f"Error reading test report: {e}")

# Read source files and timestamps
for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    file_info = {"content": "", "mtime": 0}
    try:
        if os.path.exists(full_path):
            file_info["mtime"] = int(os.path.getmtime(full_path))
            with open(full_path, "r", encoding="utf-8") as f:
                file_info["content"] = f.read()
    except Exception as e:
        print(f"Warning: error reading {full_path}: {e}")
    
    result["files"][rel_path] = file_info

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported results to {RESULT_FILE}")
PYEXPORT

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export Complete ==="