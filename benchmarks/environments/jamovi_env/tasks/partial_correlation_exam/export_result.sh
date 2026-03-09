#!/bin/bash
echo "=== Exporting partial_correlation_exam results ==="

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
OMV_PATH="/home/ga/Documents/Jamovi/ExamAnxiety_PartialCorr.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/partial_correlation_report.txt"

# 1. Check OMV Project File
OMV_EXISTS="false"
OMV_SIZE="0"
OMV_CREATED_DURING_TASK="false"

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH" 2>/dev/null || echo "0")
    OMV_MTIME=$(stat -c %Y "$OMV_PATH" 2>/dev/null || echo "0")
    
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Text Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Read content safely (limit size to prevent issues)
    REPORT_CONTENT=$(head -c 1000 "$REPORT_PATH" | base64 -w 0)
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check App State
APP_RUNNING=$(pgrep -f "org.jamovi.jamovi" > /dev/null && echo "true" || echo "false")

# 4. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_size_bytes": $OMV_SIZE,
    "omv_created_during_task": $OMV_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"