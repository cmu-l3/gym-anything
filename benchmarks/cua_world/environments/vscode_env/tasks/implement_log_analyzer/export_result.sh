#!/bin/bash
set -e

echo "=== Exporting Implement Log Analyzer Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
WORKSPACE_DIR="/home/ga/workspace/log_analyzer"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus VSCode and save all files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# ──────────────────────────────────────────────────────────
# SECURE TEST EVALUATION
# ──────────────────────────────────────────────────────────
EVAL_DIR="/tmp/eval_workspace"
sudo rm -rf "$EVAL_DIR"
mkdir -p "$EVAL_DIR"
cp -r "$WORKSPACE_DIR/log_analyzer" "$EVAL_DIR/"
mkdir -p "$EVAL_DIR/tests"
# Use the hidden, untampered tests
cp -r /var/lib/log_analyzer_tests/* "$EVAL_DIR/tests/"

cd "$EVAL_DIR"
# Run pytest on the host code against untouched tests
export PYTHONPATH="$EVAL_DIR"
python3 -m pytest tests/ -v > /tmp/pytest_output.txt 2>&1 || true

# ──────────────────────────────────────────────────────────
# PACKAGE RESULTS TO JSON
# ──────────────────────────────────────────────────────────
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"
eval_dir = "$EVAL_DIR"
result_file = "/tmp/log_analyzer_result.json"

modules = ["parser.py", "analyzer.py", "filter.py", "alerter.py", "reporter.py"]
files_data = {}
mtimes = {}

for mod in modules:
    path = os.path.join(workspace, "log_analyzer", mod)
    try:
        with open(path, "r", encoding="utf-8") as f:
            files_data[mod] = f.read()
        mtimes[mod] = int(os.path.getmtime(path))
    except Exception as e:
        files_data[mod] = f"ERROR: {e}"
        mtimes[mod] = 0

try:
    with open("/tmp/pytest_output.txt", "r", encoding="utf-8") as f:
        pytest_out = f.read()
except:
    pytest_out = ""

output_dict = {
    "task_start_time": $TASK_START,
    "files": files_data,
    "mtimes": mtimes,
    "pytest_output": pytest_out,
    "screenshot_path": "/tmp/task_final.png"
}

with open(result_file, "w", encoding="utf-8") as out:
    json.dump(output_dict, out, indent=2)

print(f"Exported to {result_file}")
PYEXPORT

chmod 666 /tmp/log_analyzer_result.json
echo "=== Export Complete ==="