#!/bin/bash
echo "=== Exporting Task Results ==="

# Define paths
OMV_PATH="/home/ga/Documents/Jamovi/SleepPairedTest.omv"
TXT_PATH="/home/ga/Documents/Jamovi/paired_ttest_results.txt"
START_TIME_FILE="/tmp/task_start_time.txt"
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check OMV File (Project File)
OMV_EXISTS=false
OMV_CREATED_DURING_TASK=false
OMV_SIZE=0

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS=true
    OMV_SIZE=$(stat -c%s "$OMV_PATH")
    OMV_MTIME=$(stat -c%Y "$OMV_PATH")
    
    if [ "$OMV_MTIME" -ge "$TASK_START" ]; then
        OMV_CREATED_DURING_TASK=true
    fi
fi

# 3. Check TXT File (Results Summary)
TXT_EXISTS=false
TXT_CREATED_DURING_TASK=false
TXT_CONTENT=""

if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS=true
    TXT_MTIME=$(stat -c%Y "$TXT_PATH")
    
    if [ "$TXT_MTIME" -ge "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK=true
    fi
    
    # Read content safely (base64 to avoid JSON breaking chars)
    TXT_CONTENT=$(base64 -w 0 "$TXT_PATH")
fi

# 4. Check if Jamovi is running
APP_RUNNING=false
if pgrep -f "org.jamovi.jamovi" > /dev/null || pgrep -f "jamovi" > /dev/null; then
    APP_RUNNING=true
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING_TASK,
    "omv_size": $OMV_SIZE,
    "txt_exists": $TXT_EXISTS,
    "txt_created_during_task": $TXT_CREATED_DURING_TASK,
    "txt_content_base64": "$TXT_CONTENT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"