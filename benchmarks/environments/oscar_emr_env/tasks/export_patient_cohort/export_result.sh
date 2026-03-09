#!/bin/bash
# Export script for Export Patient Cohort task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/2020_cohort.csv"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_SIZE=0
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Read content (head to avoid massive dumps if they export whole DB)
    # Convert potential binary/excel garbage to readable text if possible, or just raw read
    # If it's CSV/Text, cat it. If Excel, we might just see binary header, handled in python.
    # Simple safeguard: read first 2KB
    FILE_CONTENT=$(head -c 2000 "$OUTPUT_PATH" | tr -d '\000') 
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_PATH",
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "file_content_sample": $(echo "$FILE_CONTENT" | jq -R -s '.'),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"