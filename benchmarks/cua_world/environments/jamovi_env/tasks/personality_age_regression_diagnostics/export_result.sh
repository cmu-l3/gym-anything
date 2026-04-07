#!/bin/bash
echo "=== Exporting personality_age_regression_diagnostics results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_PATH="/home/ga/Documents/Jamovi/Personality_Age.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/age_analysis_report.txt"
RESULT_JSON="/tmp/task_result.json"

# Check Project File (.omv)
if [ -f "$PROJECT_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    OMV_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")

    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING_TASK="true"
    else
        OMV_CREATED_DURING_TASK="false"
    fi
else
    OMV_EXISTS="false"
    OMV_SIZE="0"
    OMV_CREATED_DURING_TASK="false"
fi

# Check Report File (.txt)
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")

    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    else
        REPORT_CREATED_DURING_TASK="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_CREATED_DURING_TASK="false"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "jamovi" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result using temp file pattern
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING_TASK,
    "omv_size_bytes": $OMV_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "omv_path": "$PROJECT_PATH",
    "report_path": "$REPORT_PATH"
}
EOF

# Move to final location with permission fallback
rm -f "$RESULT_JSON" 2>/dev/null || sudo rm -f "$RESULT_JSON" 2>/dev/null || true
mv "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON" 2>/dev/null || sudo chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="
