#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting escape_room_audio_puzzle Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

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

# Check for exported file and anti-gaming timestamp
EXPORT_PATH="/home/ga/Audio/escape_room/puzzle_clue.wav"
EXPORT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
EXPORT_SIZE=0

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    # Check if they named it something else but put it in the folder
    ALT_FILE=$(find /home/ga/Audio/escape_room/ -name "*.wav" -type f 2>/dev/null | head -1)
    if [ -n "$ALT_FILE" ]; then
        EXPORT_PATH="$ALT_FILE"
        EXPORT_EXISTS="true"
        EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
        EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
        
        if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/escape_room_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "export_exists": $EXPORT_EXISTS,
    "export_path": "$EXPORT_PATH",
    "export_size_bytes": $EXPORT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/escape_room_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/escape_room_result.json 2>/dev/null || true
chmod 666 /tmp/escape_room_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/escape_room_result.json"
echo "=== Export Complete ==="