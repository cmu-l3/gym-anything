#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Autograder Task Result ==="

WORKSPACE_DIR="/home/ga/workspace/autograder"
RESULT_FILE="/tmp/autograder_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1

echo "Saving all files..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Take final screenshot
take_screenshot /tmp/task_final.png

# Remove any stale result file
rm -f "$RESULT_FILE"

# Run the grader to capture scores and extract source files
python3 << PYEXPORT
import json, os, subprocess

workspace = "$WORKSPACE_DIR"

# Run the grader
scores = {}
try:
    res = subprocess.run(
        ["python3", "run_grader.py"], 
        cwd=workspace, 
        capture_output=True, 
        text=True, 
        timeout=15
    )
    if res.returncode == 0:
        scores = json.loads(res.stdout)
    else:
        scores = {"error": "Script crashed", "stderr": res.stderr}
except Exception as e:
    scores = {"error": str(e)}

files_to_export = {
    "test_runner.py": os.path.join(workspace, "test_runner.py"),
    "output_comparator.py": os.path.join(workspace, "output_comparator.py"),
    "score_calculator.py": os.path.join(workspace, "score_calculator.py"),
    "test_parser.py": os.path.join(workspace, "test_parser.py"),
}

source_files = {}
for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            source_files[label] = f.read()
    except Exception as e:
        source_files[label] = f"ERROR: {e}"

result = {
    "scores": scores,
    "source_files": source_files,
    "task_start_time": open("/tmp/task_start_time.txt").read().strip() if os.path.exists("/tmp/task_start_time.txt") else "0"
}

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported result to $RESULT_FILE")
PYEXPORT

echo "=== Export Complete ==="