#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Commercial Audio Bed Edit Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Trigger a save and close Ardour cleanly to flush changes to XML
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    echo "Ardour is running, attempting graceful save..."
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
SESSION_EXISTS="false"
SESSION_MODIFIED="false"

if [ -f "$SESSION_FILE" ]; then
    SESSION_EXISTS="true"
    SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    if [ "$SESSION_MTIME" -gt "$TASK_START" ]; then
        SESSION_MODIFIED="true"
    fi
fi

# Create export JSON
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "session_file_exists": $SESSION_EXISTS,
    "session_modified_during_task": $SESSION_MODIFIED,
    "session_file_path": "$SESSION_FILE"
}
EOF

# Safely move JSON to predictable location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export Complete ==="