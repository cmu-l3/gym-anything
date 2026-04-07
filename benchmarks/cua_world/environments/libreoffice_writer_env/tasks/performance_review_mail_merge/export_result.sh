#!/bin/bash
echo "=== Exporting Performance Review Mail Merge Result ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/performance_reviews_final.odt"
TEMPLATE_PATH="/home/ga/Documents/review_letter_template.odt"

# Check output file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Check if template was modified (anti-gaming: agent shouldn't just rename the template)
TEMPLATE_EXISTS="false"
if [ -f "$TEMPLATE_PATH" ]; then
    TEMPLATE_EXISTS="true"
fi

# Check original doc hash
ORIGINAL_HASH=$(cat /tmp/original_doc_hash.txt 2>/dev/null || echo "")
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_HASH=$(md5sum "$OUTPUT_PATH" 2>/dev/null | awk '{print $1}' || echo "")
else
    OUTPUT_HASH=""
fi

if [ "$ORIGINAL_HASH" = "$OUTPUT_HASH" ] && [ -n "$ORIGINAL_HASH" ]; then
    OUTPUT_IS_COPY_OF_TEMPLATE="true"
else
    OUTPUT_IS_COPY_OF_TEMPLATE="false"
fi

# Check if LibreOffice is still running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null 2>&1 && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON
TEMP=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "template_still_exists": $TEMPLATE_EXISTS,
    "output_is_copy_of_template": $OUTPUT_IS_COPY_OF_TEMPLATE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP"

cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
