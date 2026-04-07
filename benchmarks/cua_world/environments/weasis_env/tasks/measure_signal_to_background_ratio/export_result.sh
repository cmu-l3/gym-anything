#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Capture the final state screenshot before any cleanup
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TEXT_FILE="/home/ga/DICOM/exports/bone_air_ratio.txt"
IMG_FILE="/home/ga/DICOM/exports/qa_rois.png"

APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Use Python to safely parse timestamps, file existence, and content to JSON
python3 << PYEOF
import json
import os
import stat

task_start = int("$TASK_START")
text_file = "$TEXT_FILE"
img_file = "$IMG_FILE"

result = {
    "task_start": task_start,
    "text_exists": False,
    "img_exists": False,
    "created_during_task": False,
    "text_content": "",
    "app_was_running": "$APP_RUNNING" == "true",
    "screenshot_path": "/tmp/task_final.png"
}

# Process the text report
if os.path.exists(text_file):
    result["text_exists"] = True
    mtime = os.stat(text_file).st_mtime
    if mtime > task_start:
        result["created_during_task"] = True
    
    # Safely read file content
    with open(text_file, 'r', errors='ignore') as f:
        result["text_content"] = f.read(2048)

# Process the image export
if os.path.exists(img_file):
    result["img_exists"] = True
    mtime = os.stat(img_file).st_mtime
    if mtime > task_start:
        result["created_during_task"] = True

# Write out the payload for the host verifier
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

# Fix permissions so the framework can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="