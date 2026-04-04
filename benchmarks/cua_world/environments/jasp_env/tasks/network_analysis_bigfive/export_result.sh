#!/bin/bash
echo "=== Exporting network_analysis_bigfive results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JASP_FILE="/home/ga/Documents/JASP/BigFiveNetwork.jasp"
REPORT_FILE="/home/ga/Documents/JASP/network_report.txt"

# Check JASP project file
JASP_EXISTS="false"
JASP_SIZE="0"
JASP_CREATED_DURING="false"
if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE")
    if [ "$JASP_MTIME" -ge "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# Check Report file
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CREATED_DURING="false"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

# Check if JASP is still running
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_size": $JASP_SIZE,
    "jasp_created_during_task": $JASP_CREATED_DURING,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_size": $REPORT_SIZE,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "app_running": $APP_RUNNING,
    "final_screenshot": "/tmp/task_final.png"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="