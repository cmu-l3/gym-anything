#!/bin/bash
echo "=== Exporting Fix Typos and Language Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/Presentations/global_health_summit.odp"

# Check output file status
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    OUTPUT_EXISTS="false"
    FILE_MODIFIED="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "output_mtime": $OUTPUT_MTIME,
    "output_path": "$OUTPUT_PATH",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="