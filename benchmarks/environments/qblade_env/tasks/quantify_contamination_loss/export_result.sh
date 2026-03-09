#!/bin/bash
echo "=== Exporting Contamination Loss Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Task Metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Path definitions
PROJECT_PATH="/home/ga/Documents/projects/contamination_study.wpa"
REPORT_PATH="/home/ga/Documents/contamination_report.txt"

# 3. Verify Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Verify Report File & Content
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content, limit size just in case
    REPORT_CONTENT=$(head -n 20 "$REPORT_PATH" | base64 -w 0)
    
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 5. Check QBlade State
APP_RUNNING=$(is_qblade_running)

# 6. Construct JSON Result
# We embed the Base64 report content so Python can parse the numbers safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "project_exists": $PROJECT_EXISTS,
    "project_size_bytes": $PROJECT_SIZE,
    "project_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Save result with permissions
write_result_json "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm -f "$TEMP_JSON"

echo "=== Export complete ==="