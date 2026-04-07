#!/bin/bash
echo "=== Exporting radio_broadcast_midroll_insertion result ==="

source /workspace/scripts/task_utils.sh

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
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPORT_PATH="/home/ga/Audio/broadcast/final_mix.wav"

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
else
    EXPORT_EXISTS="false"
    EXPORT_SIZE="0"
    EXPORT_MTIME="0"
fi

# Create JSON result using a temporary file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "export_exists": $EXPORT_EXISTS,
    "export_size": $EXPORT_SIZE,
    "export_mtime": $EXPORT_MTIME,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date +%s)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/radio_broadcast_midroll_insertion_result.json 2>/dev/null || sudo rm -f /tmp/radio_broadcast_midroll_insertion_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/radio_broadcast_midroll_insertion_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/radio_broadcast_midroll_insertion_result.json
chmod 666 /tmp/radio_broadcast_midroll_insertion_result.json 2>/dev/null || sudo chmod 666 /tmp/radio_broadcast_midroll_insertion_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/radio_broadcast_midroll_insertion_result.json"
echo "=== Export Complete ==="