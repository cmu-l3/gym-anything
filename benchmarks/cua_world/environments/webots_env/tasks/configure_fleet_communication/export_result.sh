#!/bin/bash
set -e
echo "=== Exporting Configure Fleet Communication task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Paths
OUTPUT_FILE="/home/ga/Desktop/warehouse_comms.wbt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write metadata result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "output_path": "$OUTPUT_FILE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="