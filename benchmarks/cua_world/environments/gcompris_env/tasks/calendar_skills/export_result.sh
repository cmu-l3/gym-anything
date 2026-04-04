#!/bin/bash
echo "=== Exporting Calendar Skills Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Log File
LOG_FILE="/home/ga/Documents/calendar_log.txt"
LOG_EXISTS="false"
LOG_CREATED_DURING="false"
LINE_COUNT=0
LOG_CONTENT=""

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        LOG_CREATED_DURING="true"
    fi
    
    # Count lines (dates found)
    LINE_COUNT=$(wc -l < "$LOG_FILE" || echo "0")
    
    # Read content (first 10 lines max) for verification context
    LOG_CONTENT=$(head -n 10 "$LOG_FILE" | tr '\n' '; ')
fi

# 2. Check App State
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "log_file_exists": $LOG_EXISTS,
    "log_created_during_task": $LOG_CREATED_DURING,
    "log_line_count": $LINE_COUNT,
    "log_content_preview": "$LOG_CONTENT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="