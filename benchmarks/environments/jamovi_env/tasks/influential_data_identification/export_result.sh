#!/bin/bash
echo "=== Exporting task results ==="

# 1. Record end time and retrieve start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Define expected paths
REPORT_PATH="/home/ga/Documents/Jamovi/influential_student_report.txt"
PROJECT_PATH="/home/ga/Documents/Jamovi/Influential_Analysis.omv"
DATASET_PATH="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

# 3. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    # Read content (safe read, limit size)
    REPORT_CONTENT=$(head -c 1000 "$REPORT_PATH" | base64 -w 0)
fi

# 4. Check Project File
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH")
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING="true"
    fi
fi

# 5. Check if Jamovi is still running
APP_RUNNING=$(pgrep -f "org.jamovi.jamovi" > /dev/null && echo "true" || echo "false")

# 6. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 7. Create JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "report_content_b64": "$REPORT_CONTENT",
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING,
    "app_running": $APP_RUNNING,
    "dataset_path": "$DATASET_PATH"
}
EOF

# 8. Move to standard location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="