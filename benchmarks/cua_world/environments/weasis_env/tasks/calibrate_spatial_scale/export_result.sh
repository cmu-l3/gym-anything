#!/bin/bash
echo "=== Exporting calibrate_spatial_scale result ==="

source /workspace/scripts/task_utils.sh

# Take final desktop screenshot
take_screenshot /tmp/task_final.png

EXPORT_PATH="/home/ga/DICOM/exports/calibrated_scale.jpg"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EXPORT_EXISTS="false"
CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Check if application was still running
APP_RUNNING="false"
if pgrep -f "weasis" > /dev/null; then
    APP_RUNNING="true"
fi

# Save to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "export_exists": $EXPORT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="