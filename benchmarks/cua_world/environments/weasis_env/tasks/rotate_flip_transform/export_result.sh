#!/bin/bash
echo "=== Exporting rotate_flip_transform task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

EXPORT_FILE="/home/ga/DICOM/exports/transformed_view.jpg"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
CREATED_DURING_TASK="false"

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPORT_FILE" 2>/dev/null || stat -f %z "$EXPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || stat -f %m "$EXPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Detect if Weasis is still running
WEASIS_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "weasis_running": $WEASIS_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="