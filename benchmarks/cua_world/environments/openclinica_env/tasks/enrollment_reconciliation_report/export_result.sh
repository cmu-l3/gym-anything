#!/bin/bash
echo "=== Exporting enrollment_reconciliation_report result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

REPORT_FILE="/home/ga/Documents/enrollment_reconciliation.txt"
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# We don't need to parse the file in bash, we'll let verifier.py copy the file and parse it.
# Create the JSON result file
TEMP_JSON=$(mktemp /tmp/enrollment_report_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/enrollment_report_result.json 2>/dev/null || sudo rm -f /tmp/enrollment_report_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/enrollment_report_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/enrollment_report_result.json
chmod 666 /tmp/enrollment_report_result.json 2>/dev/null || sudo chmod 666 /tmp/enrollment_report_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export JSON created."
echo "=== Export complete ==="