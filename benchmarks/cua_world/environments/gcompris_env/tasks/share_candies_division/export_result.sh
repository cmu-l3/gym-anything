#!/bin/bash
echo "=== Exporting Share the Candies result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Text File
TEXT_FILE="/home/ga/Documents/candy_problem.txt"
TEXT_EXISTS="false"
TEXT_CREATED_DURING_TASK="false"
TEXT_CONTENT=""

if [ -f "$TEXT_FILE" ]; then
    TEXT_EXISTS="true"
    TEXT_MTIME=$(stat -c %Y "$TEXT_FILE" 2>/dev/null || echo "0")
    if [ "$TEXT_MTIME" -gt "$TASK_START" ]; then
        TEXT_CREATED_DURING_TASK="true"
    fi
    # Read first line of content (up to 100 chars)
    TEXT_CONTENT=$(head -n 1 "$TEXT_FILE" | cut -c1-100)
fi

# 2. Check Agent Screenshot
SCREENSHOT_FILE="/home/ga/Documents/candy_success.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$SCREENSHOT_FILE" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_FILE" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check App State
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# 4. Capture Final System Screenshot (for VLM verification)
# We capture this regardless of whether the agent took one
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "text_file_exists": $TEXT_EXISTS,
    "text_created_during_task": $TEXT_CREATED_DURING_TASK,
    "text_content": "$TEXT_CONTENT",
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "system_final_screenshot": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="