#!/bin/bash
set -e
echo "=== Exporting Fifteen Puzzle results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the specific screenshot file exists and was created during the task
OUTPUT_PATH="/home/ga/Documents/fifteen_puzzle_solved.png"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if GCompris is still running (it should be)
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Take a final system screenshot (evidence of final screen state)
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $FILE_EXISTS,
    "output_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "system_screenshot_path": "/tmp/task_final.png",
    "agent_screenshot_path": "$OUTPUT_PATH"
}
EOF

# Move result to final location with permissive permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="