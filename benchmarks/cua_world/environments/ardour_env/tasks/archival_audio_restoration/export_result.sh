#!/bin/bash
echo "=== Exporting Archival Audio Restoration Result ==="

source /workspace/scripts/task_utils.sh

# Capture final UI state
take_screenshot /tmp/task_final.png

# Tell Ardour to save cleanly if running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 2
    fi
    kill_ardour
fi
sleep 1

# Check for expected export file
EXPORT_PATH="/home/ga/Audio/archive_master/tape_0042_restored.flac"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

EXPORT_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_TYPE="unknown"
CREATED_DURING_TASK="false"

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    # Use 'file' command to verify it's actually a FLAC file (prevents WAV renaming gaming)
    FILE_TYPE=$(file -b --mime-type "$EXPORT_PATH" 2>/dev/null || echo "unknown")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Package JSON results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "export_exists": $EXPORT_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_type": "$FILE_TYPE",
    "created_during_task": $CREATED_DURING_TASK
}
EOF

# Move to final readable location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "JSON result exported."
echo "=== Export Complete ==="