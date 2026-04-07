#!/bin/bash
set -e
echo "=== Exporting extract_location_extremes result ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_PATH="/home/ga/Documents/sund_rock_records.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written."
echo "=== Export complete ==="