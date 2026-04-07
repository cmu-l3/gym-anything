#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Vinyl EP Sequencing Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Determine if Ardour was running at the end
APP_RUNNING="false"
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    APP_RUNNING="true"
    # Attempt to gracefully save the session before pulling data
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

# Check if session file was modified during task
SESSION_EXISTS="false"
SESSION_MODIFIED="false"

if [ -f "$SESSION_FILE" ]; then
    SESSION_EXISTS="true"
    SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    if [ "$SESSION_MTIME" -gt "$TASK_START" ]; then
        SESSION_MODIFIED="true"
    fi
fi

# Write results to JSON for the verifier
TEMP_JSON=$(mktemp /tmp/vinyl_task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "session_exists": $SESSION_EXISTS,
    "session_modified": $SESSION_MODIFIED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to standard path
rm -f /tmp/vinyl_task_result.json 2>/dev/null || sudo rm -f /tmp/vinyl_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/vinyl_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/vinyl_task_result.json
chmod 666 /tmp/vinyl_task_result.json 2>/dev/null || sudo chmod 666 /tmp/vinyl_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/vinyl_task_result.json"
echo "=== Export Complete ==="