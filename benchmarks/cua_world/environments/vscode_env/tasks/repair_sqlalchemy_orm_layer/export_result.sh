#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Repair SQLAlchemy ORM Layer Result ==="

WORKSPACE_DIR="/home/ga/workspace/orm_project"
RESULT_FILE="/tmp/orm_task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove any stale result file
rm -f "$RESULT_FILE"

# Collect file modification times for anti-gaming checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MODELS_MTIME=$(stat -c %Y "$WORKSPACE_DIR/models.py" 2>/dev/null || echo "0")
REPO_MTIME=$(stat -c %Y "$WORKSPACE_DIR/repository.py" 2>/dev/null || echo "0")

MODELS_MODIFIED="false"
REPO_MODIFIED="false"
if [ "$MODELS_MTIME" -gt "$TASK_START" ]; then MODELS_MODIFIED="true"; fi
if [ "$REPO_MTIME" -gt "$TASK_START" ]; then REPO_MODIFIED="true"; fi

# Extract file contents into JSON
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "models.py": os.path.join(workspace, "models.py"),
    "repository.py": os.path.join(workspace, "repository.py")
}

result = {
    "task_start_time": $TASK_START,
    "models_modified": $MODELS_MODIFIED,
    "repo_modified": $REPO_MODIFIED,
    "files": {}
}

for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["files"][label] = f.read()
    except Exception as e:
        result["files"][label] = None

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

PYEXPORT

echo "=== Export Complete ==="