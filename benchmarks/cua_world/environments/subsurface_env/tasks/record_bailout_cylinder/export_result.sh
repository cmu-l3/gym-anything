#!/bin/bash
set -e
echo "=== Exporting record_bailout_cylinder task result ==="

export DISPLAY="${DISPLAY:-:1}"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/ssrf_initial_mtime.txt 2>/dev/null || echo "0")

# Check if output file was modified
OUTPUT_PATH="/home/ga/Documents/dives.ssrf"
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    else
        FILE_MODIFIED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    FILE_MODIFIED_DURING_TASK="false"
    OUTPUT_SIZE="0"
fi

# Check if Subsurface is still running
APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_mtime": $INITIAL_MTIME,
    "output_mtime": ${OUTPUT_MTIME:-0},
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="