#!/bin/bash
# export_result.sh - Post-task hook for flash_point_hot_work_assessment
set -e

echo "=== Exporting task results ==="

# 1. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# 2. Check Output File
OUTPUT_PATH="/home/ga/Documents/hot_work_flash_point_assessment.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Verify file was modified AFTER task start
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Application State
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Capture Final Screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "output_path": "$OUTPUT_PATH"
}
EOF

# 6. Move result to standard location (handle permissions)
RESULT_DEST="/tmp/task_result.json"
rm -f "$RESULT_DEST" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_DEST"
chmod 666 "$RESULT_DEST" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to $RESULT_DEST"
cat "$RESULT_DEST"

echo "=== Export complete ==="