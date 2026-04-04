#!/bin/bash
echo "=== Exporting Task Result ==="

TARGET_FILE="/home/ga/Documents/Presentations/quarterly_review.odp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot (evidence of UI state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if file exists
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    FILE_HASH=$(md5sum "$TARGET_FILE" | awk '{print $1}')
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
    FILE_HASH=""
fi

# Check if file was modified during task
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    WAS_MODIFIED="true"
else
    WAS_MODIFIED="false"
fi

# Compare with original hash
ORIGINAL_HASH=$(cat /tmp/original_file.md5 2>/dev/null | awk '{print $1}' || echo "none")
if [ "$FILE_HASH" != "$ORIGINAL_HASH" ] && [ "$FILE_HASH" != "" ]; then
    CONTENT_CHANGED="true"
else
    CONTENT_CHANGED="false"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$TARGET_FILE",
    "was_modified": $WAS_MODIFIED,
    "content_changed": $CONTENT_CHANGED,
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json