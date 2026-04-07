#!/bin/bash
# Export script for configure_asv_hydrodynamics task

echo "=== Exporting configure_asv_hydrodynamics result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/asv_configured.wbt"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes, Modified: $OUTPUT_MTIME)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON (using a temporary file to avoid permission issues)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_path": "$OUTPUT_FILE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/configure_asv_result.json 2>/dev/null || sudo rm -f /tmp/configure_asv_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_asv_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_asv_result.json
chmod 666 /tmp/configure_asv_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_asv_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/configure_asv_result.json"
cat /tmp/configure_asv_result.json

echo "=== Export Complete ==="