#!/bin/bash
set -e
echo "=== Exporting MV3 Migration Task Result ==="

WORKSPACE_DIR="/home/ga/workspace/price_tracker_ext"
RESULT_FILE="/tmp/mv3_migration_result.json"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Force VSCode to save all files
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key ctrl+k s 2>/dev/null || true
sleep 1

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract code artifacts into a JSON file for the verifier
python3 << EOF
import json
import os
import sys

workspace_dir = "$WORKSPACE_DIR"
result_file = "$RESULT_FILE"
task_start = $TASK_START
task_end = $TASK_END

result = {
    "task_start": task_start,
    "task_end": task_end,
    "manifest_content": "",
    "manifest_error": "",
    "background_content": "",
    "background_error": "",
    "files_modified_during_task": False
}

# 1. Read and Parse manifest.json
manifest_path = os.path.join(workspace_dir, "manifest.json")
try:
    with open(manifest_path, "r", encoding="utf-8") as f:
        content = f.read()
        result["manifest_content"] = content
        
    mtime = os.path.getmtime(manifest_path)
    if mtime > task_start:
        result["files_modified_during_task"] = True
except Exception as e:
    result["manifest_error"] = str(e)

# 2. Read background.js
bg_path = os.path.join(workspace_dir, "background.js")
try:
    with open(bg_path, "r", encoding="utf-8") as f:
        content = f.read()
        result["background_content"] = content

    mtime = os.path.getmtime(bg_path)
    if mtime > task_start:
        result["files_modified_during_task"] = True
except Exception as e:
    result["background_error"] = str(e)

# Write to tmp location safely
with open(result_file, "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)
EOF

chmod 666 "$RESULT_FILE"
echo "Exported extension code to $RESULT_FILE"
echo "=== Export Complete ==="