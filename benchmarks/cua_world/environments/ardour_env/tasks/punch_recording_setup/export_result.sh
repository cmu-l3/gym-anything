#!/bin/bash
echo "=== Exporting punch_recording_setup Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save the session if Ardour is running (failsafe in case agent did UI but forgot Ctrl+S)
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    echo "Ardour is running. Triggering save..."
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    # Gracefully close Ardour
    kill_ardour
fi

sleep 2

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Read timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_session_mtime.txt 2>/dev/null || echo "0")
CURRENT_MTIME="0"
if [ -f "$SESSION_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi

SESSION_MODIFIED="false"
if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -ge "$TASK_START" ]; then
    SESSION_MODIFIED="true"
fi

# Create export JSON file
TEMP_JSON=$(mktemp /tmp/punch_setup_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "session_modified": $SESSION_MODIFIED,
    "task_start_timestamp": $TASK_START,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure safe copying
rm -f /tmp/punch_setup_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/punch_setup_result.json 2>/dev/null
chmod 666 /tmp/punch_setup_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/punch_setup_result.json"
echo "=== Export Complete ==="