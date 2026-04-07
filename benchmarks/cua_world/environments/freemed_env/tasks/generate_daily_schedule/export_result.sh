#!/bin/bash
echo "=== Exporting generate_daily_schedule results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if expected PDF was created
OUTPUT_PATH="/home/ga/Documents/daily_schedule.pdf"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

    # Anti-gaming check: File must be created after the task started
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Record container's understanding of today's date for verifier cross-reference
CONTAINER_DATE_ISO=$(date +%Y-%m-%d)
CONTAINER_DATE_US=$(date +%m/%d/%Y)

# Build JSON result using a temporary file
TEMP_JSON=$(mktemp /tmp/daily_schedule_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "container_date_iso": "$CONTAINER_DATE_ISO",
    "container_date_us": "$CONTAINER_DATE_US",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON securely to target path
rm -f /tmp/daily_schedule_result.json 2>/dev/null || sudo rm -f /tmp/daily_schedule_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/daily_schedule_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/daily_schedule_result.json
chmod 666 /tmp/daily_schedule_result.json 2>/dev/null || sudo chmod 666 /tmp/daily_schedule_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/daily_schedule_result.json"
cat /tmp/daily_schedule_result.json

echo "=== Export complete ==="