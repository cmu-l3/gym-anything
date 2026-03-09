#!/bin/bash
set -e
echo "=== Exporting Canal Lock Activity results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if screenshot file exists and was created during the task
SCREENSHOT_PATH="/home/ga/canal_lock_complete.png"
SCREENSHOT_EXISTS="false"
FILE_VALID="false"
FILE_SIZE="0"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    FILE_TIME=$(stat -c%Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    # Check if modified after task start
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILE_VALID="true"
    fi
fi

# 2. Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# 3. Take final screenshot for evidence
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid_timestamp": $FILE_VALID,
    "screenshot_size_bytes": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="