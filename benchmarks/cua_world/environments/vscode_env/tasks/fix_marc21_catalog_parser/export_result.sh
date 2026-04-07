#!/bin/bash
set -e
echo "=== Exporting MARC21 Parser Result ==="

source /workspace/scripts/task_utils.sh
WORKSPACE_DIR="/home/ga/workspace/marc_parser"
RESULT_FILE="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Save open files in VSCode
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1

cd "$WORKSPACE_DIR"

# Ensure output is generated if the agent fixed code but forgot to run it
if [ ! -f "output/parsed_catalog.json" ]; then
    sudo -u ga python3 run_conversion.py > /dev/null 2>&1 || true
fi

# Run tests to capture test output
sudo -u ga pytest test_parser.py > /tmp/pytest_output.txt 2>&1 || true

# Package results
python3 << PYEXPORT
import json
import os

workspace = "$WORKSPACE_DIR"
result = {
    "task_start_time": 0,
    "parser_mtime": 0,
    "parser_code": "",
    "pytest_output": "",
    "parsed_json": None
}

if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt", "r") as f:
        result["task_start_time"] = int(f.read().strip())

parser_path = os.path.join(workspace, "parser.py")
if os.path.exists(parser_path):
    result["parser_mtime"] = int(os.path.getmtime(parser_path))
    with open(parser_path, "r", encoding="utf-8") as f:
        result["parser_code"] = f.read()

if os.path.exists("/tmp/pytest_output.txt"):
    with open("/tmp/pytest_output.txt", "r", encoding="utf-8") as f:
        result["pytest_output"] = f.read()

output_json_path = os.path.join(workspace, "output/parsed_catalog.json")
if os.path.exists(output_json_path):
    try:
        with open(output_json_path, "r", encoding="utf-8") as f:
            result["parsed_json"] = json.load(f)
    except:
        result["parsed_json"] = "INVALID_JSON"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)
PYEXPORT

echo "Export complete: $RESULT_FILE"