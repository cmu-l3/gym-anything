#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Telephone Futz EQ Design Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Attempt to save the session gracefully if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    echo "Ardour is running. Attempting to save session..."
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    # Force close
    kill_ardour
fi

sleep 1

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Read baseline
INITIAL_TRACKS=$(cat /tmp/initial_track_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check session file modification
SESSION_MTIME="0"
SESSION_MODIFIED_DURING_TASK="false"
if [ -f "$SESSION_FILE" ]; then
    SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    if [ "$SESSION_MTIME" -gt "$TASK_START" ]; then
        SESSION_MODIFIED_DURING_TASK="true"
    fi
fi

# Create result JSON
cat > /tmp/telephone_futz_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "session_modified_during_task": $SESSION_MODIFIED_DURING_TASK,
    "initial_track_count": $INITIAL_TRACKS,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/telephone_futz_result.json"
echo "=== Export Complete ==="