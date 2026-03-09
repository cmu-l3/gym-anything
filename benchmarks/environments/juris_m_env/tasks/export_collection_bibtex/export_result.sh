#!/bin/bash
echo "=== Exporting export_collection_bibtex result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EXPECTED_PATH="/home/ga/Documents/first_amendment_refs.bib"

# Check if output file exists and was created during task
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$EXPECTED_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$EXPECTED_PATH" 2>/dev/null || echo "0")
    
    OUTPUT_MTIME=$(stat -c %Y "$EXPECTED_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    # Check for alternate naming (common user error)
    ALT_FILE=$(find /home/ga/Documents -name "*.bib" -type f -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$ALT_FILE" ]; then
        echo "Found alternate bib file: $ALT_FILE"
        EXPECTED_PATH="$ALT_FILE"
        OUTPUT_EXISTS="true"
        FILE_CREATED_DURING_TASK="true"
        OUTPUT_SIZE=$(stat -c %s "$ALT_FILE" 2>/dev/null || echo "0")
    fi
fi

# Check if Jurism was running
APP_RUNNING=$(pgrep -f "jurism" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_path": "$EXPECTED_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="