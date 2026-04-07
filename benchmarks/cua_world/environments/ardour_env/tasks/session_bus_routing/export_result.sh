#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Session Bus Routing Result ==="

# Take final screenshot before altering state
take_screenshot /tmp/task_end_screenshot.png

# Trigger a save and close if Ardour is still running
ARDOUR_RUNNING="false"
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    ARDOUR_RUNNING="true"
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

# Read baseline metrics
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_session_mtime 2>/dev/null || echo "0")
CURRENT_MTIME="0"

if [ -f "$SESSION_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi

SESSION_MODIFIED="false"
if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
    SESSION_MODIFIED="true"
fi

# Write summary JSON
cat > /tmp/task_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "ardour_was_running": $ARDOUR_RUNNING,
    "session_modified": $SESSION_MODIFIED,
    "task_start_timestamp": $TASK_START,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="