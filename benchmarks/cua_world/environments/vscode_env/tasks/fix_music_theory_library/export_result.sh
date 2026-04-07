#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Music Theory Library Result ==="

WORKSPACE_DIR="/home/ga/workspace/music_theory_lib"
RESULT_FILE="/tmp/music_theory_result.json"

# Save all open files in VSCode
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 2

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Run the test suite and capture the output
echo "Running pytest to capture test results..."
cd "$WORKSPACE_DIR"
TEST_OUTPUT=$(sudo -u ga python3 -m pytest tests/ -v --tb=short 2>&1 || true)
TEST_EXIT_CODE=$?

# Export all source files and test results to JSON
python3 << PYEXPORT
import json
import os

workspace = "$WORKSPACE_DIR"
test_output = """$TEST_OUTPUT"""
test_exit_code = $TEST_EXIT_CODE

files_to_export = {
    "music_theory/interval_calculator.py": os.path.join(workspace, "music_theory", "interval_calculator.py"),
    "music_theory/chord_analyzer.py":      os.path.join(workspace, "music_theory", "chord_analyzer.py"),
    "music_theory/key_detector.py":        os.path.join(workspace, "music_theory", "key_detector.py"),
    "music_theory/transposer.py":          os.path.join(workspace, "music_theory", "transposer.py")
}

result = {
    "test_output": test_output,
    "test_exit_code": test_exit_code,
    "files": {}
}

for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["files"][label] = f.read()
    except FileNotFoundError:
        result["files"][label] = None
    except Exception as e:
        result["files"][label] = f"ERROR: {e}"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files and test results to $RESULT_FILE")
PYEXPORT

chmod 666 "$RESULT_FILE"

echo "=== Export Complete ==="