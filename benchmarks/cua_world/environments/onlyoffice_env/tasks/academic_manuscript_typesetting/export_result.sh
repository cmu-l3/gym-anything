#!/bin/bash
set -e

echo "=== Exporting Academic Manuscript Typesetting Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target output file
OUTPUT_PATH="/home/ga/Documents/TextDocuments/typeset_manuscript.docx"

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check output file status
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

# Check if OnlyOffice was running
APP_RUNNING=$(pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null && echo "true" || echo "false")

# Save results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final accessible location
cp "$TEMP_JSON" /tmp/typeset_task_result.json
chmod 666 /tmp/typeset_task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/typeset_task_result.json"
cat /tmp/typeset_task_result.json
echo "=== Export complete ==="