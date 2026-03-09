#!/bin/bash
set -e

echo "=== Exporting BCP Draft Watermark Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/bcp_plan_draft.docx"
SOURCE_PATH="/home/ga/Documents/bcp_plan.docx"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if source file was modified (it shouldn't be)
SOURCE_MODIFIED="false"
CURRENT_HASH=$(md5sum "$SOURCE_PATH" 2>/dev/null | awk '{print $1}' || echo "missing")
ORIGINAL_HASH=$(cat /tmp/original_hash.txt 2>/dev/null || echo "stored_missing")

if [ "$CURRENT_HASH" != "$ORIGINAL_HASH" ]; then
    SOURCE_MODIFIED="true"
    echo "WARNING: Source file was modified!"
fi

# Check if Writer is still running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "source_modified": $SOURCE_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="