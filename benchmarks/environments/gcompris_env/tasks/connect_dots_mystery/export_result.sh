#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Screenshot Evidence
SCREENSHOT_PATH="/home/ga/Documents/solved_dots.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"
SCREENSHOT_CREATED_DURING="false"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    # Check file size (> 5KB ensures it's not empty)
    SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$SIZE" -gt 5000 ]; then
        SCREENSHOT_VALID="true"
    fi
    # Check timestamp
    MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING="true"
    fi
fi

# 2. Check Text Report Evidence
TEXT_PATH="/home/ga/Documents/object_id.txt"
TEXT_EXISTS="false"
TEXT_CONTENT=""
TEXT_CREATED_DURING="false"

if [ -f "$TEXT_PATH" ]; then
    TEXT_EXISTS="true"
    TEXT_CONTENT=$(cat "$TEXT_PATH" | head -n 1) # Read first line
    MTIME=$(stat -c %Y "$TEXT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        TEXT_CREATED_DURING="true"
    fi
fi

# 3. Check App State
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Take Final System Screenshot (for VLM verification)
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid": $SCREENSHOT_VALID,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING,
    "text_file_exists": $TEXT_EXISTS,
    "text_content": "$(echo "$TEXT_CONTENT" | sed 's/"/\\"/g')", 
    "text_created_during_task": $TEXT_CREATED_DURING,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="