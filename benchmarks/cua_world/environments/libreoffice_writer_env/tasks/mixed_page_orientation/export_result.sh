#!/bin/bash
# export_result.sh for mixed_page_orientation task
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# Define paths
OUTPUT_FILE="/home/ga/Documents/bcp_formatted.docx"
TASK_START_FILE="/tmp/task_start_time.txt"

# Get task start time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check output file status
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "task_start_time": $TASK_START,
    "export_timestamp": "$(date +%s)"
}
EOF

# Save result to predictable location with proper permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Close Writer gracefully if possible
safe_xdotool ga :1 key ctrl+q || true
sleep 1
safe_xdotool ga :1 key alt+d || true # Don't save changes dialog if it appears

echo "=== Export Complete ==="