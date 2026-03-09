#!/bin/bash
echo "=== Exporting Export Patient Audit Log Result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DATE=$(cat /tmp/task_date_iso.txt 2>/dev/null || date -I)

OUTPUT_PATH="/home/ga/Documents/brandie_sammet_audit.csv"
RESULT_JSON="/tmp/task_result.json"

# 1. Check File Existence and Metadata
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING="true"
    fi
fi

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# 3. Create JSON Result
# We will copy the CSV content to a temp location for the python verifier to read
# if the file exists.
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_date": "$TASK_DATE",
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "output_path": "$OUTPUT_PATH"
}
EOF

# 4. Make files accessible to verifier
chmod 644 "$RESULT_JSON"
if [ "$FILE_EXISTS" == "true" ]; then
    cp "$OUTPUT_PATH" /tmp/audit_log_export.csv
    chmod 644 /tmp/audit_log_export.csv
fi

echo "Export complete. Result saved to $RESULT_JSON"