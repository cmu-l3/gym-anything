#!/bin/bash
echo "=== Exporting Reading Practice Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Log File
LOG_PATH="/home/ga/Documents/reading_log.txt"
LOG_EXISTS="false"
LOG_CREATED_DURING_TASK="false"
LOG_LINE_COUNT=0
LOG_CONTENT_PREVIEW=""

if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    
    # Check timestamp
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
        LOG_CREATED_DURING_TASK="true"
    fi
    
    # Count lines (words)
    LOG_LINE_COUNT=$(wc -l < "$LOG_PATH" || echo "0")
    
    # Read content for verifier (first 10 lines)
    LOG_CONTENT_PREVIEW=$(head -n 10 "$LOG_PATH" | tr '\n' '|')
fi

# 2. Check App State
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "log_exists": $LOG_EXISTS,
    "log_created_during_task": $LOG_CREATED_DURING_TASK,
    "log_line_count": $LOG_LINE_COUNT,
    "log_content_preview": "$LOG_CONTENT_PREVIEW",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="