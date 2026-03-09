#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/Jamovi/analysis_decision.txt"
OMV_PATH="/home/ga/Documents/Jamovi/InsectAnalysis.omv"
DATASET_PATH="/home/ga/Documents/Jamovi/InsectSprays.csv"

# Check Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Check if created during task
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    else
        REPORT_CREATED_DURING="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_SIZE="0"
    REPORT_CREATED_DURING="false"
fi

# Check OMV File
if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH" 2>/dev/null || echo "0")
    OMV_MTIME=$(stat -c %Y "$OMV_PATH" 2>/dev/null || echo "0")
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING="true"
    else
        OMV_CREATED_DURING="false"
    fi
else
    OMV_EXISTS="false"
    OMV_SIZE="0"
    OMV_CREATED_DURING="false"
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "jamovi" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "report_size": $REPORT_SIZE,
    "report_path": "$REPORT_PATH",
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING,
    "omv_size": $OMV_SIZE,
    "omv_path": "$OMV_PATH",
    "dataset_path": "$DATASET_PATH",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="