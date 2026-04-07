#!/bin/bash
set -e

echo "=== Exporting Fix Document Image Registration Result ==="

source /workspace/scripts/task_utils.sh

WORKSPACE_DIR="/home/ga/workspace/doc_processor"
RESULT_FILE="/tmp/doc_registration_result.json"

# Save open files in VSCode
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Run pytest and capture results
echo "Running pytest to capture test results..."
PYTEST_OUTPUT=$(su - ga -c "cd $WORKSPACE_DIR && pytest tests/ -v" 2>&1 || true)
PYTEST_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c "PASSED" || echo "0")
PYTEST_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c "FAILED" || echo "0")

# Package everything into JSON
python3 << PYEXPORT
import json
import os

workspace = "$WORKSPACE_DIR"
files = {
    "aligner": "pipeline/aligner.py",
    "preprocessor": "pipeline/preprocessor.py",
    "roi_extractor": "pipeline/roi_extractor.py"
}

result = {
    "pytest_passed": $PYTEST_PASSED,
    "pytest_failed": $PYTEST_FAILED,
    "pytest_output": """$PYTEST_OUTPUT""",
    "files": {}
}

for name, rel_path in files.items():
    try:
        with open(os.path.join(workspace, rel_path), "r") as f:
            result["files"][name] = f.read()
    except Exception as e:
        result["files"][name] = f"ERROR: {str(e)}"

with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)

print(f"Result exported successfully to $RESULT_FILE")
PYEXPORT

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "=== Export Complete ==="