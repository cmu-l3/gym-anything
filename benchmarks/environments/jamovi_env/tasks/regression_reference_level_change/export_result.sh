#!/bin/bash
echo "=== Exporting Regression Reference Level Results ==="

# Source timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File Paths
OMV_PATH="/home/ga/Documents/Jamovi/InsectSprays_Ref_F.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/coefficients_report.txt"

# Check OMV File
OMV_EXISTS="false"
OMV_VALID_TIME="false"
OMV_SIZE=0

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH")
    OMV_MTIME=$(stat -c %Y "$OMV_PATH")
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_VALID_TIME="true"
    fi
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_VALID_TIME="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_VALID_TIME="true"
    fi
    # Read first 500 chars of report for verification script to parse
    REPORT_CONTENT=$(head -c 500 "$REPORT_PATH" | base64 -w 0)
fi

# Check if Jamovi is still running
APP_RUNNING="false"
if pgrep -f "jamovi" > /dev/null; then
    APP_RUNNING="true"
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_valid_time": $OMV_VALID_TIME,
    "omv_size": $OMV_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_valid_time": $REPORT_VALID_TIME,
    "report_content_b64": "$REPORT_CONTENT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"