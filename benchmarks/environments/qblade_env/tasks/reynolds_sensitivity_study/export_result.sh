#!/bin/bash
echo "=== Exporting Reynolds Study Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_FILE="/home/ga/Documents/reynolds_study_report.txt"
PROJECT_FILE="/home/ga/Documents/projects/reynolds_study.wpa"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content (safe read, limit size)
    REPORT_CONTENT=$(head -c 5000 "$REPORT_FILE" | base64 -w 0)
fi

# 3. Check Project File
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING_TASK="false"
PROJECT_SIZE=0
if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$PROJECT_FILE")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
    PROJECT_SIZE=$(stat -c %s "$PROJECT_FILE")
fi

# 4. Check if QBlade is still running
APP_RUNNING="false"
if pgrep -f "QBlade" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
cat > /tmp/task_result_temp.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_base64": "$REPORT_CONTENT",
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "project_size_bytes": $PROJECT_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (permission safe)
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"