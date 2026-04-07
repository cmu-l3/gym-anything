#!/bin/bash
echo "=== Exporting Selective Measurement Deletion task result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_PATH="/home/ga/DICOM/exports/selective_deletion.png"

# Validate output file
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_CREATED_DURING_TASK="false"
FILE_MTIME=0

if [ -f "$EXPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Determine if Weasis is still running
WEASIS_RUNNING="false"
if pgrep -f "weasis" > /dev/null 2>&1; then
    WEASIS_RUNNING="true"
fi

# Write results to JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "file_mtime": $FILE_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "weasis_running": $WEASIS_RUNNING,
    "screenshot_path": "/tmp/task_end.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="