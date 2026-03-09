#!/bin/bash
echo "=== Exporting factorial_anova results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_PATH="/home/ga/Documents/Jamovi/ToothGrowth_ANOVA.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/anova_report.txt"

# Check Project File
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    else
        PROJECT_CREATED_DURING_TASK="false"
    fi
else
    PROJECT_EXISTS="false"
    PROJECT_SIZE="0"
    PROJECT_CREATED_DURING_TASK="false"
fi

# Check Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    else
        REPORT_CREATED_DURING_TASK="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_SIZE="0"
    REPORT_CREATED_DURING_TASK="false"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Jamovi is still running
APP_RUNNING=$(pgrep -f "jamovi" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size_bytes": $PROJECT_SIZE,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_size_bytes": $REPORT_SIZE,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Copy output files to /tmp for easy extraction by verifier.py
if [ "$REPORT_EXISTS" == "true" ]; then
    cp "$REPORT_PATH" /tmp/anova_report_content.txt
    chmod 666 /tmp/anova_report_content.txt
fi

echo "=== Export complete ==="