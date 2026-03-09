#!/bin/bash
echo "=== Exporting Task Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define Paths
OMV_PATH="/home/ga/Documents/Jamovi/ToothGrowth_EffectSize.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/effect_size_report.txt"

# Check OMV File
OMV_EXISTS="false"
OMV_CREATED_DURING_TASK="false"
OMV_SIZE=0

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH")
    OMV_MTIME=$(stat -c %Y "$OMV_PATH")
    if [ "$OMV_MTIME" -ge "$TASK_START" ]; then
        OMV_CREATED_DURING_TASK="true"
    fi
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content (safe read)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1024)
fi

# Check App State
APP_RUNNING=$(pgrep -f "org.jamovi.jamovi" > /dev/null && echo "true" || echo "false")

# Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create Result JSON
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
    "report_content": $(echo "$REPORT_CONTENT" | jq -R .),
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json