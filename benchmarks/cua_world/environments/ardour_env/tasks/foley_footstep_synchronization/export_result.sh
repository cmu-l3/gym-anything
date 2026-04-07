#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Foley Synchronization Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Gracefully save and close if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
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
SESSION_MTIME="0"

if [ -f "$SESSION_FILE" ]; then
    SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Create result JSON
cat > /tmp/foley_footstep_synchronization_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "session_mtime": $SESSION_MTIME,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/foley_footstep_synchronization_result.json"
echo "=== Export Complete ==="