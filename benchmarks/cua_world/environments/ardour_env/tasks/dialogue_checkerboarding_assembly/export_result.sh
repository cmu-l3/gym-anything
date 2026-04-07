#!/bin/bash
echo "=== Exporting Dialogue Checkerboarding Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE closing
take_screenshot /tmp/task_end_screenshot.png

# Send save command if Ardour is active
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

# Verify modification status (Anti-gaming)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_mtime 2>/dev/null || echo "0")
CURRENT_MTIME="0"
SESSION_MODIFIED="false"

if [ -f "$SESSION_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        SESSION_MODIFIED="true"
    fi
fi

# Create result payload
TEMP_JSON=$(mktemp /tmp/checkerboard_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "session_modified": $SESSION_MODIFIED,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)",
    "final_screenshot": "/tmp/task_end_screenshot.png"
}
EOF

# Move payload safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result payload saved to /tmp/task_result.json"
echo "=== Export Complete ==="