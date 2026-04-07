#!/bin/bash
echo "=== Exporting dark_ride_audio_sync Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running (Graceful shutdown to flush XML changes)
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

# Check exported file
EXPORT_FILE="/home/ga/Audio/ride_export/ride_reference.wav"
EXPORT_EXISTS="false"
EXPORT_SIZE=0
EXPORT_CREATED_DURING_TASK="false"

if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_FILE" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
        EXPORT_CREATED_DURING_TASK="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "export_exists": $EXPORT_EXISTS,
    "export_size_bytes": $EXPORT_SIZE,
    "export_created_during_task": $EXPORT_CREATED_DURING_TASK,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/dark_ride_result.json 2>/dev/null || sudo rm -f /tmp/dark_ride_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/dark_ride_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/dark_ride_result.json
chmod 666 /tmp/dark_ride_result.json 2>/dev/null || sudo chmod 666 /tmp/dark_ride_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/dark_ride_result.json"
echo "=== Export Complete ==="