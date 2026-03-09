#!/bin/bash
echo "=== Exporting capture_client_debug_logs results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
# If the agent closed Firefox as requested, this might show the terminal or desktop
take_screenshot /tmp/task_final.png

# 2. Check the log file
LOG_PATH="/home/ga/Documents/firefox_console.log"
LOG_EXISTS="false"
LOG_SIZE="0"
LOG_MTIME="0"
FILE_CREATED_DURING_TASK="false"
CONTAINS_CONTENT="false"

if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_SIZE=$(stat -c %s "$LOG_PATH" 2>/dev/null || echo "0")
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    
    # Check creation time
    if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check if not empty
    if [ "$LOG_SIZE" -gt 100 ]; then
        CONTAINS_CONTENT="true"
    fi
    
    # Prepare file for verifier (copy to /tmp/task_log_capture.txt)
    # This ensures permissions are correct for the verifier script to read it
    cp "$LOG_PATH" /tmp/task_log_capture.txt
    chmod 644 /tmp/task_log_capture.txt
else
    # Create empty placeholder to prevent copy errors
    touch /tmp/task_log_capture.txt
fi

# 3. Check if Firefox is still running (Agent should have closed it)
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "log_exists": $LOG_EXISTS,
    "log_size_bytes": $LOG_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "firefox_running": $FIREFOX_RUNNING,
    "contains_content": $CONTAINS_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="