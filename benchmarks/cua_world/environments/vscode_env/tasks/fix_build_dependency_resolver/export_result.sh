#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Build System Result ==="

WORKSPACE_DIR="/home/ga/workspace/buildsys"
RESULT_FILE="/tmp/buildsys_result.json"

# Best-effort: save all open files in VSCode
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

rm -f "$RESULT_FILE"

# Collect all modified files into a single JSON artifact
python3 << PYEXPORT
import json
import os

workspace = "$WORKSPACE_DIR"
files_to_export = [
    "resolver/version.py",
    "resolver/dependency_graph.py",
    "resolver/constraint_solver.py",
    "scheduler/topo_sort.py",
    "scheduler/cache_manager.py"
]

result = {}
for rel_path in files_to_export:
    path = os.path.join(workspace, rel_path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            result[rel_path] = f.read()
    except Exception as e:
        result[rel_path] = f"ERROR: {e}"
        print(f"Warning: could not read {path}")

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "=== Export Complete ==="