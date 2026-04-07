#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Backup Script Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
WORKSPACE_DIR="/home/ga/workspace/backup_system"
RESULT_FILE="/tmp/task_result.json"

# Capture final screenshot before acting
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

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

# Collect all relevant bash scripts into a single JSON dict
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "backup_manager.sh": os.path.join(workspace, "backup_manager.sh"),
    "lib/common.sh":     os.path.join(workspace, "lib", "common.sh"),
    "lib/db_backup.sh":  os.path.join(workspace, "lib", "db_backup.sh"),
    "lib/fs_backup.sh":  os.path.join(workspace, "lib", "fs_backup.sh"),
}

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "sources": {}
}

for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["sources"][label] = f.read()
    except Exception as e:
        result["sources"][label] = f"ERROR: {e}"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

PYEXPORT

chmod 666 "$RESULT_FILE"
echo "=== Export Complete ==="
ls -la "$RESULT_FILE" 2>/dev/null || echo "Warning: result file not created"