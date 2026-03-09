#!/bin/bash
echo "=== Exporting CERCLA RQ Assessment Results ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/cercla_spill_report.txt"

# 1. Check Output File Status
if [ -f "$REPORT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# 2. Check App Status
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "report_path": "$REPORT_PATH"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="