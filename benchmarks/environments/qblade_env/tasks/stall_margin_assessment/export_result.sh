#!/bin/bash
echo "=== Exporting Stall Margin Assessment Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Report File
REPORT_PATH="/home/ga/Documents/stall_margin_report.txt"
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check Project File
PROJECT_PATH="/home/ga/Documents/projects/stall_assessment.wpa"
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING_TASK="false"
PROJECT_SIZE=0

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_PATH")
    
    if [ "$PROJECT_MTIME" -ge "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# 5. Check App Status
APP_RUNNING="false"
if pgrep -f "QBlade" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create Result JSON
# We include the report content inline if it exists to simplify verification
# But we also copy the file itself in a moment.
RESULT_JSON_PATH="/tmp/task_result.json"

cat > "$RESULT_JSON_PATH" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size": $REPORT_SIZE,
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "project_size": $PROJECT_SIZE,
    "app_running": $APP_RUNNING,
    "report_path": "$REPORT_PATH",
    "project_path": "$PROJECT_PATH"
}
EOF

# 7. Prepare files for safe copy (chmod)
chmod 644 "$RESULT_JSON_PATH" 2>/dev/null || true
if [ -f "$REPORT_PATH" ]; then chmod 644 "$REPORT_PATH" 2>/dev/null || true; fi

echo "Export complete. Result saved to $RESULT_JSON_PATH"
cat "$RESULT_JSON_PATH"