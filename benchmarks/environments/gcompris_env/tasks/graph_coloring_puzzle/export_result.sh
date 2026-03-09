#!/bin/bash
echo "=== Exporting Graph Coloring Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screen state (for VLM)
take_screenshot /tmp/task_final.png

# 2. Check for user-created screenshot
EXPECTED_PATH="/home/ga/graph_solved.png"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$EXPECTED_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPECTED_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPECTED_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"