#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting ASMR Haas Stereo Widening Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running (Anti-gaming / ensures flush to disk)
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
INITIAL_MTIME=$(cat /tmp/initial_session_mtime 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Current state
CURRENT_MTIME="0"
SESSION_MODIFIED="false"
if [ -f "$SESSION_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        SESSION_MODIFIED="true"
    fi
fi

# Create basic result JSON to indicate the framework state
cat > /tmp/asmr_haas_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "session_modified": $SESSION_MODIFIED,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

echo "Result saved to /tmp/asmr_haas_result.json"
echo "=== Export Complete ==="