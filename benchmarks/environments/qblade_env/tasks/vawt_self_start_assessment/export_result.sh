#!/bin/bash
echo "=== Exporting VAWT Self-Start Assessment Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_FILE="/home/ga/Documents/projects/vawt_selfstart.wpa"
REPORT_FILE="/home/ga/Documents/projects/vawt_selfstart_report.txt"

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_CREATED_DURING_TASK="false"

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_FILE" 2>/dev/null || echo "0")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_FILE" 2>/dev/null || echo "0")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read content, limit to 1KB to prevent massive JSON injection
    REPORT_CONTENT=$(head -c 1024 "$REPORT_FILE")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if QBlade is still running
APP_RUNNING=$(is_qblade_running)
if [ "$APP_RUNNING" -gt 0 ]; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
# We use Python to safely escape the report content for JSON
python3 -c "
import json
import sys

try:
    report_content = '''$REPORT_CONTENT'''
except:
    report_content = ''

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'project_exists': $PROJECT_EXISTS,
    'project_size_bytes': $PROJECT_SIZE,
    'project_created_during_task': $PROJECT_CREATED_DURING_TASK,
    'report_exists': $REPORT_EXISTS,
    'report_created_during_task': $REPORT_CREATED_DURING_TASK,
    'report_content': report_content,
    'app_was_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions so the host can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="