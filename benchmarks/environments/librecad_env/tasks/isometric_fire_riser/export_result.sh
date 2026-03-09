#!/bin/bash
set -e
echo "=== Exporting Isometric Fire Riser results ==="

# Define paths
OUTPUT_FILE="/home/ga/Documents/LibreCAD/fire_riser_iso.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing anything
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if file exists
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    # Verify file was created/modified DURING the task
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Check if App is still running
if pgrep -f "librecad" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "output_path": "$OUTPUT_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="