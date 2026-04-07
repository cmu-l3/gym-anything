#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Game Audio Seamless Loop Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Determine if Ardour is running
APP_RUNNING="false"
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    APP_RUNNING="true"
    # Attempt to gracefully save the session before extracting data
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 2
    fi
    kill_ardour
fi

sleep 1

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Read baseline
INITIAL_MTIME=$(cat /tmp/initial_session_mtime 2>/dev/null || echo "0")

# Current state
SESSION_EXISTS="false"
CURRENT_MTIME="0"
SESSION_SAVED="false"

if [ -f "$SESSION_FILE" ]; then
    SESSION_EXISTS="true"
    CURRENT_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -ge "$TASK_START" ]; then
        SESSION_SAVED="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/loop_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "session_file_exists": $SESSION_EXISTS,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "session_saved_during_task": $SESSION_SAVED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/game_audio_seamless_loop_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/game_audio_seamless_loop_result.json
chmod 666 /tmp/game_audio_seamless_loop_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/game_audio_seamless_loop_result.json"
echo "=== Export Complete ==="