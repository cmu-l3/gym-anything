#!/bin/bash
echo "=== Exporting annotate_finding task results ==="

source /workspace/scripts/task_utils.sh

# Record end state screenshot
take_screenshot /tmp/task_end_screenshot.png

# Paths and targets
EXPORT_PATH="/home/ga/DICOM/exports/annotated_finding.jpg"
TASK_START_FILE="/tmp/task_start_time.txt"

# Get task start time
TASK_START=0
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
fi

# Check for the exported JPEG file
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
CREATED_DURING_TASK="false"
VALID_JPEG="false"

if [ -f "$EXPORT_PATH" ]; then
    FILE_EXISTS="true"
    
    # Get file size and modification time
    FILE_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || stat -f %z "$EXPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || stat -f %m "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    # Check if created after task started
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Check if it's actually a valid JPEG file (checks magic bytes FFD8)
    HEADER=$(xxd -p -l 2 "$EXPORT_PATH" 2>/dev/null || echo "")
    if [[ "$HEADER" == "ffd8" || "$HEADER" == "FFD8" ]]; then
        VALID_JPEG="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "created_during_task": $CREATED_DURING_TASK,
    "valid_jpeg": $VALID_JPEG,
    "export_path": "$EXPORT_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Make result readable and move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="