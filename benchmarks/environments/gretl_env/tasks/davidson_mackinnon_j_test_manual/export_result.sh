#!/bin/bash
echo "=== Exporting J-Test Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUT_LINEAR="/home/ga/Documents/gretl_output/aux_linear.txt"
OUT_LOG="/home/ga/Documents/gretl_output/aux_log.txt"

# Check Aux Linear File
if [ -f "$OUT_LINEAR" ]; then
    LINEAR_EXISTS="true"
    LINEAR_SIZE=$(stat -c %s "$OUT_LINEAR" 2>/dev/null || echo "0")
    LINEAR_MTIME=$(stat -c %Y "$OUT_LINEAR" 2>/dev/null || echo "0")
    if [ "$LINEAR_MTIME" -gt "$TASK_START" ]; then
        LINEAR_CREATED_DURING_TASK="true"
    else
        LINEAR_CREATED_DURING_TASK="false"
    fi
else
    LINEAR_EXISTS="false"
    LINEAR_SIZE="0"
    LINEAR_CREATED_DURING_TASK="false"
fi

# Check Aux Log File
if [ -f "$OUT_LOG" ]; then
    LOG_EXISTS="true"
    LOG_SIZE=$(stat -c %s "$OUT_LOG" 2>/dev/null || echo "0")
    LOG_MTIME=$(stat -c %Y "$OUT_LOG" 2>/dev/null || echo "0")
    if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
        LOG_CREATED_DURING_TASK="true"
    else
        LOG_CREATED_DURING_TASK="false"
    fi
else
    LOG_EXISTS="false"
    LOG_SIZE="0"
    LOG_CREATED_DURING_TASK="false"
fi

# Check if Gretl was running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "aux_linear_exists": $LINEAR_EXISTS,
    "aux_linear_created_during_task": $LINEAR_CREATED_DURING_TASK,
    "aux_linear_size": $LINEAR_SIZE,
    "aux_log_exists": $LOG_EXISTS,
    "aux_log_created_during_task": $LOG_CREATED_DURING_TASK,
    "aux_log_size": $LOG_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="