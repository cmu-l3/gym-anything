#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Mix-Minus Routing Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running to ensure XML is fully flushed
APP_WAS_RUNNING="false"
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    APP_WAS_RUNNING="true"
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 1

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

FILE_MODIFIED_DURING_TASK="false"
if [ -f "$SESSION_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Create result JSON securely
TEMP_JSON=$(mktemp /tmp/mix_minus_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "app_was_running": $APP_WAS_RUNNING,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $TASK_END
}
EOF

# Move into place securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="