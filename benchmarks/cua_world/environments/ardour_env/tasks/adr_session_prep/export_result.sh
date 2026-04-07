#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting ADR Session Prep Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
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

# Read baseline
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check session modification time
SESSION_MTIME="0"
if [ -f "$SESSION_FILE" ]; then
    SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Create result JSON
cat > /tmp/adr_session_prep_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "task_start_timestamp": $TASK_START,
    "session_mtime": $SESSION_MTIME,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/adr_session_prep_result.json"
echo "=== Export Complete ==="