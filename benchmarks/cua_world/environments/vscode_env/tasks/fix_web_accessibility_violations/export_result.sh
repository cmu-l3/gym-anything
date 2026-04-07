#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Web Accessibility Remediations Result ==="

WORKSPACE_DIR="/home/ga/workspace/agency_dashboard"
RESULT_FILE="/tmp/a11y_result.json"

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

# Collect all relevant source files and their modification times
python3 << PYEXPORT
import json
import os

workspace = "$WORKSPACE_DIR"

files_to_export = [
    "index.html",
    "login.html",
    "reports.html",
    "css/styles.css",
    "js/dashboard.js"
]

result = {}
for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    file_data = {
        "content": "",
        "mtime": 0,
        "exists": False
    }
    try:
        if os.path.exists(full_path):
            with open(full_path, "r", encoding="utf-8") as f:
                file_data["content"] = f.read()
            file_data["mtime"] = os.path.getmtime(full_path)
            file_data["exists"] = True
    except Exception as e:
        print(f"Warning: error reading {full_path}: {e}")

    result[rel_path] = file_data

# Read task start time
try:
    with open("/tmp/task_start_time", "r") as f:
        result["task_start_time"] = float(f.read().strip())
except:
    result["task_start_time"] = 0.0

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "=== Export Complete ==="
ls -la "$RESULT_FILE" 2>/dev/null || echo "Warning: result file not created"