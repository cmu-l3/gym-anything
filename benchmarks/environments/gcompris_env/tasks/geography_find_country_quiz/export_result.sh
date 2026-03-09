#!/bin/bash
echo "=== Exporting Geography Quiz Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the user-generated screenshot exists and verify timestamp
EVIDENCE_PATH="/home/ga/Documents/geography_score.png"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$EVIDENCE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if GCompris is still running
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# 3. Take final screenshot of the actual screen state
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_file_exists": $FILE_EXISTS,
    "evidence_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "evidence_file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png",
    "user_screenshot_path": "$EVIDENCE_PATH"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="