#!/bin/bash
echo "=== Exporting call_and_response_assembly Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Try to save the Ardour session gracefully before checking XML
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    echo "Saving Ardour session..."
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    # Force kill to ensure files are flushed
    kill_ardour
fi

sleep 1

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check exported files
EXPORT_PATH="/home/ga/Audio/edtech_export/listen_and_repeat.wav"
EXPORT_EXISTS="false"
EXPORT_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    # Check if they exported to the folder but with a different name
    ANY_WAV=$(find /home/ga/Audio/edtech_export/ -name "*.wav" -type f | head -1)
    if [ -n "$ANY_WAV" ]; then
        EXPORT_EXISTS="true"
        EXPORT_SIZE=$(stat -c %s "$ANY_WAV" 2>/dev/null || echo "0")
        EXPORT_MTIME=$(stat -c %Y "$ANY_WAV" 2>/dev/null || echo "0")
        if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Create result JSON securely using a temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "export_exists": $EXPORT_EXISTS,
    "export_size_bytes": $EXPORT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="