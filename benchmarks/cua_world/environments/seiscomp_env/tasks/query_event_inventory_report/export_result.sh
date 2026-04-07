#!/bin/bash
echo "=== Exporting query_event_inventory_report result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract state for verification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/noto_earthquake_report.txt"

FILE_EXISTS="false"
FILE_MODIFIED="false"
CONTENT_JSON="\"\""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check if created/modified during task
    MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Safely JSON-encode file contents using jq
    CONTENT_JSON=$(jq -Rs . < "$OUTPUT_FILE")
fi

# 3. Create JSON output
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_MODIFIED,
    "report_content": $CONTENT_JSON
}
EOF

# Move to standard location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="