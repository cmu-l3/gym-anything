#!/bin/bash
echo "=== Exporting export_viewport_clipboard task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/DICOM/exports/clipboard_dump.png"

# Verify File
EXISTS="false"
CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$TARGET_FILE" ]; then
    EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE" 2>/dev/null || echo "0")
    MTIME=$(stat -c%Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Generate JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_exists": $EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move payload safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="