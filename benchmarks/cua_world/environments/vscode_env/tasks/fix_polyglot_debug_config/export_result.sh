#!/bin/bash
set -e

# Import utils
source /workspace/scripts/task_utils.sh || true

echo "=== Exporting Polyglot Debug Task Result ==="

WORKSPACE_DIR="/home/ga/workspace/media_pipeline"
RESULT_FILE="/tmp/polyglot_debug_result.json"

# Best-effort: save all open files in VSCode
focus_vscode_window 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key --delay 100 ctrl+shift+s 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key --delay 100 ctrl+k ctrl+s 2>/dev/null || true
sleep 1

rm -f "$RESULT_FILE"

# Collect all configurations and modified files using Python to ensure valid JSON escape
python3 << PYEXPORT
import json
import os

workspace = "$WORKSPACE_DIR"

files = {
    "launch.json": os.path.join(workspace, ".vscode", "launch.json"),
    "tasks.json": os.path.join(workspace, ".vscode", "tasks.json"),
    "api/main.py": os.path.join(workspace, "api", "main.py"),
    "worker/processor.js": os.path.join(workspace, "worker", "processor.js")
}

result = {}
for name, path in files.items():
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                result[name] = f.read()
        except Exception as e:
            result[name] = f"ERROR reading: {e}"
    else:
        result[name] = None

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

PYEXPORT

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

chmod 666 "$RESULT_FILE"
echo "Exported to $RESULT_FILE"