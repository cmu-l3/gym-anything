#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting SVG Animation Generator Result ==="

WORKSPACE_DIR="/home/ga/workspace/svg_animator"
RESULT_FILE="/tmp/svg_animator_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1

echo "Saving all files..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove any stale result file
rm -f "$RESULT_FILE"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Restore clean tests to prevent test tampering
echo "Restoring clean test suite for verification..."
cp -r /var/lib/svg_tests/* "$WORKSPACE_DIR/tests/" 2>/dev/null || true
chown -R ga:ga "$WORKSPACE_DIR/tests"

# Run pytest to generate XML report
echo "Running test suite..."
sudo -u ga python3 -m pytest "$WORKSPACE_DIR/tests/" --junit-xml=/tmp/pytest_results.xml > /dev/null 2>&1 || true

# Collect test results and source files into a single JSON
python3 << 'PYEXPORT'
import json
import os
import xml.etree.ElementTree as ET

workspace = "/home/ga/workspace/svg_animator"
result = {
    "files": {},
    "tests": {}
}

# 1. Capture source files
files_to_export = [
    "animation/interpolator.py",
    "animation/color_utils.py",
    "animation/timeline.py",
    "svg/path_builder.py",
    "svg/renderer.py"
]

for rel_path in files_to_export:
    path = os.path.join(workspace, rel_path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["files"][rel_path] = f.read()
    except Exception:
        result["files"][rel_path] = None

# 2. Parse pytest XML
try:
    tree = ET.parse('/tmp/pytest_results.xml')
    root = tree.getroot()
    # Find all testcases anywhere in the tree
    for testcase in root.iter('testcase'):
        name = testcase.get('name')
        failed = False
        for child in testcase:
            if child.tag in ['failure', 'error']:
                failed = True
        result["tests"][name] = "failed" if failed else "passed"
except Exception as e:
    result["tests"]["error"] = str(e)

with open("/tmp/svg_animator_result.json", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)
PYEXPORT

chmod 666 "$RESULT_FILE"
echo "=== Export Complete ==="