#!/bin/bash
echo "=== Exporting Factorial ANOVA results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_PATH="/home/ga/Documents/Jamovi/ToothGrowth_Interaction.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/oj_dose2_mean.txt"

# Check Project File
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    else
        PROJECT_CREATED_DURING_TASK="false"
    fi
else
    PROJECT_EXISTS="false"
    PROJECT_CREATED_DURING_TASK="false"
fi

# Check Report File
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    else
        REPORT_CREATED_DURING_TASK="false"
    fi
    # Read content (limit to 100 chars to avoid massive dumps)
    REPORT_CONTENT=$(head -c 100 "$REPORT_PATH")
else
    REPORT_EXISTS="false"
    REPORT_CREATED_DURING_TASK="false"
fi

# Check if Jamovi is still running
APP_RUNNING=$(pgrep -f "org.jamovi.jamovi" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": "$REPORT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with read permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="