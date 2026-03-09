#!/bin/bash
# Export script for Customer Segment Export task

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check for the output file
OUTPUT_PATH="/home/ga/Documents/wholesale_leads.csv"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
FILE_CONTENT_BASE64=""
ROW_COUNT="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Read file content safely (limit size)
    # Encode to base64 to handle newlines/special chars in JSON
    FILE_CONTENT_BASE64=$(head -c 50000 "$OUTPUT_PATH" | base64 -w 0)
    
    # Count rows (excluding header implies subtracting 1, but we'll send raw count)
    ROW_COUNT=$(wc -l < "$OUTPUT_PATH" 2>/dev/null || echo "0")
fi

# 3. Check for files in Downloads (common mistake location)
DOWNLOADS_COUNT=$(ls /home/ga/Downloads/*.csv 2>/dev/null | wc -l)
LATEST_DOWNLOAD=$(ls -t /home/ga/Downloads/*.csv 2>/dev/null | head -1)
DOWNLOAD_MTIME="0"
if [ -n "$LATEST_DOWNLOAD" ]; then
    DOWNLOAD_MTIME=$(stat -c%Y "$LATEST_DOWNLOAD" 2>/dev/null || echo "0")
fi

# 4. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/export_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start_time": $TASK_START,
    "row_count": $ROW_COUNT,
    "downloads_count": $DOWNLOADS_COUNT,
    "latest_download_mtime": $DOWNLOAD_MTIME,
    "file_content_base64": "$FILE_CONTENT_BASE64",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"