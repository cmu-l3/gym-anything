#!/bin/bash
echo "=== Exporting create_export_payroll_report result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOWNLOAD_DIR="/home/ga/Downloads"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database for Report Definition
REPORT_EXISTS="false"
REPORT_NAME="Engineering Payroll"
REPORT_ID=$(orangehrm_db_query "SELECT report_id FROM ohrm_report WHERE name='$REPORT_NAME';" 2>/dev/null | tr -d '[:space:]')

FILTER_CORRECT="false"
FIELDS_INCLUDE_SALARY="false"

if [ -n "$REPORT_ID" ]; then
    REPORT_EXISTS="true"
    
    # Check filters: should involve job_title (field_name might vary slightly in DB schema, checking generic link)
    # ohrm_selected_filter_field links to ohrm_filter_field. 
    # We'll check if any filter exists for this report.
    FILTER_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_selected_filter_field WHERE report_id=$REPORT_ID;" 2>/dev/null | tr -d '[:space:]')
    if [ "$FILTER_COUNT" -gt "0" ]; then
        FILTER_CORRECT="true" # Simplistic check, verifier can do better if needed
    fi

    # Check display fields for salary
    # We look for a field that resembles 'salary'
    # This query joins selected fields to display fields to check names
    SALARY_FIELD_CHECK=$(orangehrm_db_query "
        SELECT COUNT(*) 
        FROM ohrm_selected_display_field sdf
        JOIN ohrm_display_field df ON sdf.display_field_id = df.display_field_id
        WHERE sdf.report_id=$REPORT_ID AND (df.field_alias LIKE '%Salary%' OR df.name LIKE '%Salary%');" \
        2>/dev/null | tr -d '[:space:]')
    
    if [ "$SALARY_FIELD_CHECK" -gt "0" ]; then
        FIELDS_INCLUDE_SALARY="true"
    fi
fi

# 3. Check for Downloaded CSV
CSV_FOUND="false"
CSV_PATH=""
CSV_SIZE="0"
FILE_CREATED_DURING_TASK="false"

# Find the most recently modified CSV in downloads
LATEST_CSV=$(find "$DOWNLOAD_DIR" -name "*.csv" -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$LATEST_CSV" ]; then
    CSV_FOUND="true"
    CSV_PATH="$LATEST_CSV"
    CSV_SIZE=$(stat -c %s "$LATEST_CSV")
    FILE_MTIME=$(stat -c %Y "$LATEST_CSV")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Create a safe copy for the verifier to read
    cp "$LATEST_CSV" /tmp/exported_report.csv
    chmod 666 /tmp/exported_report.csv
fi

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists_in_db": $REPORT_EXISTS,
    "db_filter_set": $FILTER_CORRECT,
    "db_salary_field_present": $FIELDS_INCLUDE_SALARY,
    "csv_found": $CSV_FOUND,
    "csv_path": "$CSV_PATH",
    "csv_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_size_bytes": $CSV_SIZE,
    "exported_csv_path": "/tmp/exported_report.csv"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="