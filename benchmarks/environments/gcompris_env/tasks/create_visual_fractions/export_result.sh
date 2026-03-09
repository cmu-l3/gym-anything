#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
LOG_FILE="/home/ga/fractions_log.txt"
AGENT_SCREENSHOT="/home/ga/fraction_success.png"

# Check Log File
LOG_EXISTS="false"
LOG_CREATED_DURING_TASK="false"
LOG_CONTENT=""

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$LOG_MTIME" -ge "$TASK_START" ]; then
        LOG_CREATED_DURING_TASK="true"
    fi
    # Read the log content (up to 1KB)
    LOG_CONTENT=$(head -c 1024 "$LOG_FILE" | base64 -w 0)
fi

# Check Agent Screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$AGENT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_MTIME=$(stat -c %Y "$AGENT_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -ge "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Capture System Final Screenshot (for VLM verification)
take_screenshot /tmp/task_final.png

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "log_exists": $LOG_EXISTS,
    "log_created_during_task": $LOG_CREATED_DURING_TASK,
    "log_content_base64": "$LOG_CONTENT",
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "system_screenshot": "/tmp/task_final.png"
}
EOF

# Save result with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"