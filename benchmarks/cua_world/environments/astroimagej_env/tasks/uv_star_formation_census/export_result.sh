#!/bin/bash
echo "=== Exporting UV Star Formation Census Result ==="

source /workspace/scripts/task_utils.sh

# Capture task end time and final screenshot
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png ga

# Execute Python script to safely parse and package the results
python3 << PYEOF
import json
import os

report_path = "/home/ga/AstroImages/measurements/uv_knots_report.txt"
task_start = int("$TASK_START")

result = {
    "report_exists": False,
    "file_created_during_task": False,
    "report_content": "",
    "task_start": task_start,
    "screenshot_path": "/tmp/task_final.png"
}

if os.path.exists(report_path):
    result["report_exists"] = True
    
    # Check if the file was actually created during the task run to prevent gaming
    mtime = os.path.getmtime(report_path)
    if mtime > task_start:
        result["file_created_during_task"] = True
        
    # Read the file content safely
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="