#!/bin/bash
echo "=== Exporting stop_and_restart_stream results ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
LOG_FILE="/home/ga/Documents/OpenBCI_GUI/stream_lifecycle_log.txt"

# 3. Check App Status
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Process Log File
LOG_EXISTS="false"
LOG_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    # Read content (limit size just in case)
    LOG_CONTENT=$(head -c 1000 "$LOG_FILE")
    
    # Check creation time
    FILE_MTIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 5. Create Result JSON
# We use a python one-liner or simple cat to generate valid JSON to avoid dependency issues
# Using jq is better if available, but here we construct carefully.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape log content for JSON
SAFE_LOG_CONTENT=$(echo "$LOG_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
# Strip the outer quotes that json.dumps adds, because we put it inside quotes below
SAFE_LOG_CONTENT=${SAFE_LOG_CONTENT:1:-1}

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "log_exists": $LOG_EXISTS,
    "log_created_during_task": $FILE_CREATED_DURING_TASK,
    "log_content": "$SAFE_LOG_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result stored in /tmp/task_result.json"
cat /tmp/task_result.json