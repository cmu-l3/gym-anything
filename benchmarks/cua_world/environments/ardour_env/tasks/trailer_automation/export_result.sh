#!/bin/bash
echo "=== Exporting Trailer Automation Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Do NOT force a save (Ctrl+S) here because saving the session is part of the agent's task.
# If we save for them, we can't test if they remembered to do it.

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Check if session file exists and when it was modified
SESSION_EXISTS="false"
SESSION_MODIFIED_DURING_TASK="false"
SESSION_MTIME="0"

if [ -f "$SESSION_FILE" ]; then
    SESSION_EXISTS="true"
    SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    
    # Add a small buffer (2 seconds) to task start time to ensure it detects true user modifications
    if [ "$SESSION_MTIME" -gt "$((TASK_START + 2))" ]; then
        SESSION_MODIFIED_DURING_TASK="true"
    fi
fi

# Check if Ardour is running
ARDOUR_RUNNING="false"
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    ARDOUR_RUNNING="true"
fi

# Export details to JSON
TEMP_JSON=$(mktemp /tmp/trailer_automation_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "session_exists": $SESSION_EXISTS,
    "session_modified_during_task": $SESSION_MODIFIED_DURING_TASK,
    "session_mtime": $SESSION_MTIME,
    "ardour_running": $ARDOUR_RUNNING,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="