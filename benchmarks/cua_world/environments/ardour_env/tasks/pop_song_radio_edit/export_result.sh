#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORIGINAL_SIZE=$(cat /tmp/original_file_size.txt 2>/dev/null || echo "0")

# Take final screenshot before doing anything else
echo "Capturing final state..."
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Save the session and close Ardour cleanly
echo "Saving session..."
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "Radio_Edit_Project" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 2

# Check the exported file
OUTPUT_PATH="/home/ga/Audio/delivery/radio_edit_master.wav"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Copy the Ardour session XML to /tmp so the Python verifier can read it
SESSION_XML="/home/ga/Audio/sessions/Radio_Edit_Project/Radio_Edit_Project.ardour"
SESSION_EXISTS="false"
if [ -f "$SESSION_XML" ]; then
    SESSION_EXISTS="true"
    cp "$SESSION_XML" /tmp/session_export.ardour
    chmod 666 /tmp/session_export.ardour
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "original_size_bytes": $ORIGINAL_SIZE,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "session_exists": $SESSION_EXISTS,
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="