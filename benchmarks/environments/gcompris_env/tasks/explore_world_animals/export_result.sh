#!/bin/bash
set -e
echo "=== Exporting Explore World Animals results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/world_animals_report.txt"
SCREENSHOT_PATH="/home/ga/Documents/world_animals_screenshot.png"

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Check report file status
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content (escape quotes for JSON)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' || echo "\"\"")
    # Remove outer quotes added by json.dumps as we'll insert it into json structure manually or care needed
    # Actually, easier to let python handle the full JSON creation below
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check agent screenshot
AGENT_SCREENSHOT_EXISTS="false"
if [ -f "$SCREENSHOT_PATH" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    # Copy to tmp for potential export/viewing
    cp "$SCREENSHOT_PATH" /tmp/agent_screenshot_export.png 2>/dev/null || true
fi

# Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON using Python to handle content escaping safely
python3 -c "
import json
import os
import sys

report_path = '$REPORT_PATH'
content = ''
if os.path.exists(report_path):
    try:
        with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except:
        content = ''

result = {
    'task_start': $TASK_START,
    'report_exists': $REPORT_EXISTS,
    'report_content': content,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'agent_screenshot_exists': $AGENT_SCREENSHOT_EXISTS,
    'app_running': $APP_RUNNING,
    'final_screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="