#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check Report File
REPORT_PATH="/home/ga/Documents/projects/root_moment_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | tr -d '[:space:]' | head -n 1) # Read clean content
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check for QBlade Project File (Optional evidence)
# We look for any recently modified .wpa file
PROJECT_FOUND="false"
RECENT_PROJECTS=$(find /home/ga/Documents/projects -name "*.wpa" -newermt "@$TASK_START" 2>/dev/null)
if [ -n "$RECENT_PROJECTS" ]; then
    PROJECT_FOUND="true"
fi

# 4. Check App Status
APP_RUNNING=$(is_qblade_running)

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Construct JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "project_file_created": $PROJECT_FOUND,
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Safe Move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json