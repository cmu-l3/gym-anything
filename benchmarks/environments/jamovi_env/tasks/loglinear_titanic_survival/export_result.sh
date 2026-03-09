#!/bin/bash
echo "=== Exporting Log-Linear Titanic Survival results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OMV_PATH="/home/ga/Documents/Jamovi/TitanicLogLinear.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/loglinear_report.txt"

# 1. Check OMV file status
OMV_EXISTS="false"
OMV_CREATED_DURING_TASK="false"
OMV_SIZE="0"

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH" 2>/dev/null || echo "0")
    OMV_MTIME=$(stat -c %Y "$OMV_PATH" 2>/dev/null || echo "0")
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Report file status
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content safely (limit size)
    REPORT_CONTENT=$(head -n 10 "$REPORT_PATH" | tr '\n' '|')
fi

# 3. Check if Jamovi is still running
APP_RUNNING=$(pgrep -f "jamovi" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING_TASK,
    "omv_size_bytes": $OMV_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_preview": "$REPORT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="