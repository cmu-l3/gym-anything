#!/bin/bash
echo "=== Exporting PID Suitability Task Results ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather file status
OUTPUT_FILE="/home/ga/Documents/pid_assessment.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

FILE_EXISTS=false
FILE_SIZE=0
FILE_CREATED_DURING_TASK=false
CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    # Anti-gaming check: was file modified after task start?
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
fi

# 3. Check application state
APP_RUNNING=false
if pgrep -f firefox > /dev/null; then
    APP_RUNNING=true
fi

# 4. Create result JSON
# We treat the content carefully to avoid breaking JSON structure
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="