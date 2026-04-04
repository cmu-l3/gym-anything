#!/bin/bash
echo "=== Exporting register_visitor_group_meeting results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check for Agent-created Screenshot
AGENT_SCREENSHOT_PATH="/tmp/visitor_log_screenshot.png"
AGENT_SCREENSHOT_EXISTS="false"
AGENT_SCREENSHOT_VALID="false"

if [ -f "$AGENT_SCREENSHOT_PATH" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    # Check timestamp to ensure it was created DURING the task
    FILE_MTIME=$(stat -c %Y "$AGENT_SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        AGENT_SCREENSHOT_VALID="true"
    fi
fi

# 2. Capture System Final Screenshot (Backup/Ground Truth)
# This ensures we have visual evidence even if the agent forgets to save the file
take_screenshot /tmp/task_final_system.png

# 3. Check if Lobby Track is still running
APP_RUNNING=$(pgrep -f "LobbyTrack\|Lobby.*Track" > /dev/null && echo "true" || echo "false")

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "agent_screenshot_valid": $AGENT_SCREENSHOT_VALID,
    "agent_screenshot_path": "$AGENT_SCREENSHOT_PATH",
    "system_screenshot_path": "/tmp/task_final_system.png",
    "app_was_running": $APP_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="