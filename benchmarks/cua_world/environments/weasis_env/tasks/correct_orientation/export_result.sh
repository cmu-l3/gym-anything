#!/bin/bash
echo "=== Exporting correct_orientation task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths and initial vars
EXPECTED_EXPORT="/home/ga/DICOM/exports/corrected_orientation.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EXPORT_EXISTS="false"
EXPORT_SIZE=0
CREATED_DURING_TASK="false"
IS_VALID_PNG="false"

# Check if file exists
if [ -f "$EXPECTED_EXPORT" ]; then
    EXPORT_EXISTS="true"
    
    # Get file size
    EXPORT_SIZE=$(stat -c %s "$EXPECTED_EXPORT" 2>/dev/null || echo "0")
    
    # Check creation/modification time vs task start
    FILE_MTIME=$(stat -c %Y "$EXPECTED_EXPORT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Verify it is actually a PNG file using file command
    FILE_TYPE=$(file -b --mime-type "$EXPECTED_EXPORT" 2>/dev/null || echo "unknown")
    if [ "$FILE_TYPE" = "image/png" ]; then
        IS_VALID_PNG="true"
    fi
fi

# Check if Weasis was running
APP_RUNNING="false"
if pgrep -f "weasis" > /dev/null; then
    APP_RUNNING="true"
fi

# Write results to JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "export_exists": $EXPORT_EXISTS,
    "export_size_bytes": $EXPORT_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "is_valid_png": $IS_VALID_PNG,
    "app_running": $APP_RUNNING,
    "task_start_time": $TASK_START,
    "export_mtime": ${FILE_MTIME:-0},
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