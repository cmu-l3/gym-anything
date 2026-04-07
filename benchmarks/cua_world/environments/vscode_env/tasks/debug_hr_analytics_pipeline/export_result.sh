#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting HR Analytics Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/hr_analytics"
RESULT_FILE="/tmp/hr_analytics_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run the agent's pipeline to ensure output is fresh
echo "Running agent's pipeline..."
cd "$WORKSPACE_DIR"
sudo -u ga python3 main.py > /tmp/pipeline_stdout.log 2>&1 || true

# 3. Run the test suite
echo "Running tests..."
sudo -u ga python3 -m pytest tests/ -v > /tmp/pytest_stdout.log 2>&1 || true

# 4. Collect source files and outputs into a single JSON
python3 << 'PYEXPORT'
import json
import os

workspace = "/home/ga/workspace/hr_analytics"
result = {
    "task_start_time": int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0,
    "pipeline_stdout": "",
    "pytest_output": "",
    "files": {},
    "output_report": None,
    "expected_report": None,
}

# Read logs
for logfile, key in [("/tmp/pipeline_stdout.log", "pipeline_stdout"),
                      ("/tmp/pytest_stdout.log", "pytest_output")]:
    if os.path.exists(logfile):
        with open(logfile) as f:
            result[key] = f.read()

# Read pipeline source files
source_files = [
    "pipeline/loader.py",
    "pipeline/cleaner.py",
    "pipeline/transformer.py",
    "pipeline/analyzer.py",
    "pipeline/reporter.py",
    "config.py",
    "main.py",
    "tests/test_pipeline.py",
]

for rel in source_files:
    path = os.path.join(workspace, rel)
    if os.path.exists(path):
        with open(path) as f:
            result["files"][rel] = f.read()
    else:
        result["files"][rel] = None

# Read output report
report_path = os.path.join(workspace, "output", "quarterly_report.json")
if os.path.exists(report_path):
    with open(report_path) as f:
        result["output_report"] = json.load(f)

# Read expected report for comparison
expected_path = os.path.join(workspace, "expected_output", "quarterly_report.json")
if os.path.exists(expected_path):
    with open(expected_path) as f:
        result["expected_report"] = json.load(f)

with open("/tmp/hr_analytics_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Exported to /tmp/hr_analytics_result.json")
PYEXPORT

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export Complete ==="
