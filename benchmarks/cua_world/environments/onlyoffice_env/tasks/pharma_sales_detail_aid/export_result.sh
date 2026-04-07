#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE trying to close the app
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if ONLYOFFICE is running
APP_RUNNING=$(pgrep -f "onlyoffice-desktopeditors" > /dev/null && echo "true" || echo "false")

# Verify the expected output file
OUTPUT_PATH="/home/ga/Documents/Presentations/cardio_detail_aid.pptx"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    ACTUAL_FILENAME="cardio_detail_aid.pptx"
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
    ACTUAL_FILENAME=""
    
    # Check if they saved it with a slightly different name
    ALTERNATIVE=$(find /home/ga/Documents/Presentations -name "*.pptx" -type f -newermt "@$TASK_START" | head -n 1)
    if [ -n "$ALTERNATIVE" ]; then
        echo "Found alternative save file: $ALTERNATIVE"
        cp "$ALTERNATIVE" "$OUTPUT_PATH" 2>/dev/null || true
        OUTPUT_EXISTS="true"
        FILE_CREATED_DURING_TASK="true"
        OUTPUT_SIZE=$(stat -c %s "$ALTERNATIVE" 2>/dev/null || echo "0")
        ACTUAL_FILENAME=$(basename "$ALTERNATIVE")
    fi
fi

# Create JSON result securely via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "actual_filename": "$ACTUAL_FILENAME",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final destination
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="