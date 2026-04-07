#!/bin/bash
echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Look for the exported file in Downloads
DOWNLOAD_DIR="/home/ga/Downloads"
# Find the most recently modified xlsx file
EXPORT_FILE=$(find "$DOWNLOAD_DIR" -name "*.xlsx" -type f -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_PATH=""

if [ -n "$EXPORT_FILE" ] && [ -f "$EXPORT_FILE" ]; then
    OUTPUT_PATH="$EXPORT_FILE"
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$EXPORT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Found exported file: $EXPORT_FILE"
    
    # Copy to /tmp with a fixed name for easier handling if needed, 
    # though we will pass the original path in JSON
    cp "$EXPORT_FILE" /tmp/exported_data.xlsx
    chmod 644 /tmp/exported_data.xlsx
else
    echo "No .xlsx file found in $DOWNLOAD_DIR"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="