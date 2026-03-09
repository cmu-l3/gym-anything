#!/bin/bash
echo "=== Exporting stratified_chisquare_titanic results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OMV_PATH="/home/ga/Documents/Jamovi/TitanicStratified.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/stratified_results.txt"

# Check OMV Project File
if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH")
    OMV_MTIME=$(stat -c %Y "$OMV_PATH")
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

# Check Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
else
    REPORT_EXISTS="false"
    REPORT_CONTENT=""
fi

# App Running Check
APP_RUNNING=$(pgrep -f "org.jamovi.jamovi" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "omv_exists": $OMV_EXISTS,
    "omv_size": $OMV_SIZE,
    "omv_created_during_task": $OMV_CREATED_DURING,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="