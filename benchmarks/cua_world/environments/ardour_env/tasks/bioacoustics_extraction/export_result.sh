#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Bioacoustics Extraction Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running to ensure XML flushes to disk
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

# Check for the exported audio file
EXPORT_FILE="/home/ga/Audio/bioacoustics_export/isolated_calls.wav"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPORT_FILE" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "export_file_exists": $FILE_EXISTS,
    "export_file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "session_xml_path": "/home/ga/Audio/sessions/MyProject/MyProject.ardour",
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="