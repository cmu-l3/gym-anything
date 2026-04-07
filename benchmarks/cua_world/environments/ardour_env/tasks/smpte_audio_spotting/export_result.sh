#!/bin/bash
echo "=== Exporting SMPTE Audio Spotting Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before altering the state
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running, mimicking graceful exit
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

# Grab the modification timestamp to ensure the agent actively saved
SESSION_MTIME=0
if [ -f "$SESSION_FILE" ]; then
    SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Write verification data directly to JSON
TEMP_JSON=$(mktemp /tmp/smpte_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "session_mtime": $SESSION_MTIME,
    "task_start_time": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move file safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="