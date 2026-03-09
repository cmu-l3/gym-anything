#!/bin/bash
set -e
echo "=== Exporting Camber Effect Study Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

REPORT_PATH="/home/ga/Documents/camber_study_report.txt"
PROJECT_PATH="/home/ga/Documents/projects/camber_study.wpa"

# 3. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content (base64 encoded to handle newlines safely in JSON)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE="0"
PROJECT_CREATED_DURING_TASK="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# 5. Check QBlade State
APP_RUNNING=$(is_qblade_running)
APP_RUNNING_BOOL="false"
if [ "$APP_RUNNING" -gt "0" ]; then
    APP_RUNNING_BOOL="true"
fi

# 6. Generate JSON Result
# We use Python to generate JSON to avoid string escaping issues
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $NOW,
    'report': {
        'exists': $REPORT_EXISTS,
        'path': '$REPORT_PATH',
        'created_during_task': $REPORT_CREATED_DURING_TASK,
        'content_b64': '$REPORT_CONTENT'
    },
    'project': {
        'exists': $PROJECT_EXISTS,
        'path': '$PROJECT_PATH',
        'size_bytes': $PROJECT_SIZE,
        'created_during_task': $PROJECT_CREATED_DURING_TASK
    },
    'app_running': $APP_RUNNING_BOOL,
    'screenshots': {
        'initial': '/tmp/task_initial.png',
        'final': '/tmp/task_final.png'
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# 7. Safe permission handling for export
chmod 666 /tmp/task_result.json

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="