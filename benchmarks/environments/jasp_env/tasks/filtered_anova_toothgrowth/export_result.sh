#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
JASP_FILE="/home/ga/Documents/JASP/VC_Dose_Analysis.jasp"
REPORT_FILE="/home/ga/Documents/JASP/vc_means.txt"

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
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
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
    "jasp_file_created_during": $JASP_CREATED_DURING,
    "jasp_file_size": $JASP_SIZE,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_created_during": $REPORT_CREATED_DURING,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
echo "=== Export complete ==="