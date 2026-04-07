#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Podcast Double-Ender Sync Result ==="

# Record end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
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
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(cat /tmp/task_end_timestamp 2>/dev/null || echo "0")

SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
SESSION_MODIFIED_DURING_TASK="false"
if [ "$SESSION_MTIME" -gt "$TASK_START" ]; then
    SESSION_MODIFIED_DURING_TASK="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/sync_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "app_was_running": $APP_WAS_RUNNING,
    "session_modified_during_task": $SESSION_MODIFIED_DURING_TASK,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/podcast_sync_result.json 2>/dev/null || sudo rm -f /tmp/podcast_sync_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/podcast_sync_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/podcast_sync_result.json
chmod 666 /tmp/podcast_sync_result.json 2>/dev/null || sudo chmod 666 /tmp/podcast_sync_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/podcast_sync_result.json"
echo "=== Export Complete ==="