#!/bin/bash
echo "=== Exporting nyc_lease_walt_analysis result ==="

# Record task end time and start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_PATH="/home/ga/Documents/nyc_brooklyn_leases.xlsx"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE="0"

if [ -f "$FILE_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    
    # Check if the file was modified after the task started
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Create export JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move payload to standardized location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="