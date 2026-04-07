#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Oral History Transcript Formatting Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Bring window to front before screenshot
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

# Take final screenshot for VLM / visual evidence
take_screenshot /tmp/task_final.png

FILE_PATH="/home/ga/Documents/mt_st_helens_transcript.odt"
FILE_MODIFIED="false"
OUTPUT_EXISTS="false"

# Check if the document was modified
if [ -f "$FILE_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    stat -c "Saved file info: %n (%s bytes, mtime=%Y)" "$FILE_PATH" || true
else
    echo "Warning: $FILE_PATH is missing!"
fi

# Check if Calligra is still running
APP_RUNNING=$(pgrep -f "calligrawords" > /dev/null && echo "true" || echo "false")

# Safely close Calligra Words to ensure any pending file locks are released
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2
kill_calligra_processes

# Create JSON metadata result (safe permission handling via temp file)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="