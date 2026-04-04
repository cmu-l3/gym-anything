#!/bin/bash
echo "=== Exporting robust_ttest_heteroscedasticity results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
RESULT_TXT="/home/ga/Documents/Jamovi/robust_results.txt"
PROJECT_OMV="/home/ga/Documents/Jamovi/Spray_Comparison.omv"

# Check Project File (.omv)
if [ -f "$PROJECT_OMV" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$PROJECT_OMV" 2>/dev/null || echo "0")
    OMV_MTIME=$(stat -c %Y "$PROJECT_OMV" 2>/dev/null || echo "0")
    
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

# Check Result Text File
if [ -f "$RESULT_TXT" ]; then
    TXT_EXISTS="true"
    TXT_CONTENT=$(cat "$RESULT_TXT" | base64 -w 0) # Encode to avoid JSON breaking
    TXT_MTIME=$(stat -c %Y "$RESULT_TXT" 2>/dev/null || echo "0")
    
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK="true"
    else
        TXT_CREATED_DURING_TASK="false"
    fi
else
    TXT_EXISTS="false"
    TXT_CONTENT=""
    TXT_CREATED_DURING_TASK="false"
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
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING_TASK,
    "omv_size_bytes": $OMV_SIZE,
    "txt_exists": $TXT_EXISTS,
    "txt_created_during_task": $TXT_CREATED_DURING_TASK,
    "txt_content_base64": "$TXT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="