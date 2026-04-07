#!/bin/bash
echo "=== Exporting measure_and_export task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

EXPORT_PATH="/home/ga/DICOM/exports/annotated_measurement.jpg"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
CREATED_DURING_TASK="false"
IS_VALID_JPEG="false"

if [ -f "$EXPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    # Check if created after task start
    if [ "$FILE_MTIME" -ge "$TASK_START_TIME" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Check JPEG magic bytes (FF D8 FF)
    MAGIC=$(hexdump -n 3 -e '3/1 "%02x"' "$EXPORT_PATH" 2>/dev/null)
    if [[ "$MAGIC" == "ffd8ff"* ]]; then
        IS_VALID_JPEG="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start_time": $TASK_START_TIME,
    "created_during_task": $CREATED_DURING_TASK,
    "is_valid_jpeg": $IS_VALID_JPEG,
    "export_path": "$EXPORT_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="