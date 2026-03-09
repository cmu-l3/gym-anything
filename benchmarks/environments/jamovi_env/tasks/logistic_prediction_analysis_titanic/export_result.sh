#!/bin/bash
echo "=== Exporting task results ==="

# Record end time and read start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OMV_PATH="/home/ga/Documents/Jamovi/Titanic_Predictions.omv"
TXT_PATH="/home/ga/Documents/Jamovi/prediction_summary.txt"

# Check OMV file
OMV_EXISTS="false"
OMV_CREATED_DURING="false"
OMV_SIZE=0

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_MTIME=$(stat -c %Y "$OMV_PATH" 2>/dev/null || echo "0")
    OMV_SIZE=$(stat -c %s "$OMV_PATH" 2>/dev/null || echo "0")
    
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING="true"
    fi
fi

# Check Text Summary file
TXT_EXISTS="false"
TXT_CREATED_DURING="false"
TXT_CONTENT=""

if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    TXT_MTIME=$(stat -c %Y "$TXT_PATH" 2>/dev/null || echo "0")
    
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_CREATED_DURING="true"
    fi
    
    # Read content safely (max 500 chars to avoid huge logs)
    TXT_CONTENT=$(head -c 500 "$TXT_PATH" | base64 -w 0)
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
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING,
    "omv_size_bytes": $OMV_SIZE,
    "txt_exists": $TXT_EXISTS,
    "txt_created_during_task": $TXT_CREATED_DURING,
    "txt_content_base64": "$TXT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to expected location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="