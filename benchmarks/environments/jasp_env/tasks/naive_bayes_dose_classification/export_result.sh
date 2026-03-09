#!/bin/bash
echo "=== Exporting naive_bayes_dose_classification results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

JASP_FILE="/home/ga/Documents/JASP/NaiveBayesDose.jasp"
REPORT_FILE="/home/ga/Documents/JASP/naive_bayes_report.txt"

# Check JASP file
if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    else
        JASP_CREATED_DURING="false"
    fi
else
    JASP_EXISTS="false"
    JASP_SIZE="0"
    JASP_CREATED_DURING="false"
fi

# Check Report file
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    else
        REPORT_CREATED_DURING="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_CREATED_DURING="false"
fi

# Check if JASP is still running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_size": $JASP_SIZE,
    "jasp_created_during_task": $JASP_CREATED_DURING,
    "report_file_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="