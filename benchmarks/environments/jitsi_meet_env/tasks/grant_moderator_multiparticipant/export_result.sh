#!/bin/bash
echo "=== Exporting grant_moderator_multiparticipant results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_SCREENSHOT="/home/ga/moderator_granted.png"

# 1. Capture system-level final screenshot (what is currently on screen)
take_screenshot /tmp/task_final.png

# 2. Check the user-created screenshot (evidence of success)
USER_SCREENSHOT_EXISTS="false"
USER_SCREENSHOT_SIZE="0"
USER_SCREENSHOT_VALID="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    USER_SCREENSHOT_EXISTS="true"
    USER_SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Check timestamp to ensure it was created DURING the task
    FILE_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        USER_SCREENSHOT_VALID="true"
    fi
fi

# 3. Check browser state (number of tabs/windows)
# Using xdotool to count Firefox windows (approximate check for multi-window/tab activity if distinct windows)
# Note: Tabs in same window are harder to count via X11, but we can check if Firefox is still running.
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "firefox_running": $FIREFOX_RUNNING,
    "user_screenshot_exists": $USER_SCREENSHOT_EXISTS,
    "user_screenshot_size": $USER_SCREENSHOT_SIZE,
    "user_screenshot_valid_timestamp": $USER_SCREENSHOT_VALID,
    "user_screenshot_path": "$EXPECTED_SCREENSHOT",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="