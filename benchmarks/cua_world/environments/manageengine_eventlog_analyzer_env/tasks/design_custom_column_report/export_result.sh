#!/bin/bash
# Export results for "design_custom_column_report" task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check output CSV file
OUTPUT_PATH="/home/ga/Documents/executive_report.csv"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Database for Report Profile
# Verify if the report profile was actually saved in the system
REPORT_EXISTS_IN_DB="false"
DB_RESULT=$(ela_db_query "SELECT REPORTNAME FROM ReportConfig WHERE REPORTNAME='Executive Failed Logons'" 2>/dev/null)

if [[ "$DB_RESULT" == *"Executive Failed Logons"* ]]; then
    REPORT_EXISTS_IN_DB="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Prepare CSV Header for Python verification (safely)
# We read just the first line to verify columns
CSV_HEADER=""
if [ "$FILE_EXISTS" = "true" ]; then
    CSV_HEADER=$(head -n 1 "$OUTPUT_PATH" | tr -d '\r' | sed 's/"/\\"/g')
fi

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_profile_in_db": $REPORT_EXISTS_IN_DB,
    "csv_header": "$CSV_HEADER",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Save and Clean up
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="