#!/bin/bash
# Export script for sakila_qa_data_validation_suite task

echo "=== Exporting Sakila QA Validation Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Verify Table Existence and Structure
TABLE_INFO=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*), 
           SUM(CASE WHEN COLUMN_NAME IN ('test_id', 'test_name', 'test_description', 'records_found', 'status', 'executed_at') THEN 1 ELSE 0 END)
    FROM COLUMNS 
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='qa_test_results';
" 2>/dev/null)
TABLE_EXISTS=$(echo "$TABLE_INFO" | awk '{print $1}')
COLUMNS_MATCH=$(echo "$TABLE_INFO" | awk '{print $2}')

# 2. Verify Procedure Existence
PROC_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM ROUTINES 
    WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_NAME='sp_run_qa_suite' AND ROUTINE_TYPE='PROCEDURE';
" 2>/dev/null)

# 3. Verify Data in qa_test_results table
# We extract the results as JSON to be parsed by python
TABLE_DATA_JSON=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT JSON_ARRAYAGG(JSON_OBJECT(
        'test_name', test_name,
        'records_found', records_found,
        'status', status
    )) FROM qa_test_results;
" 2>/dev/null)

# If table is empty or doesn't exist, JSON_ARRAYAGG returns NULL
if [ "$TABLE_DATA_JSON" == "NULL" ] || [ -z "$TABLE_DATA_JSON" ]; then
    TABLE_DATA_JSON="[]"
fi

# 4. Verify CSV Export
CSV_PATH="/home/ga/Documents/exports/qa_test_results.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || echo "0")
    # Count lines minus header
    TOTAL_LINES=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

# Create result JSON
cat > /tmp/qa_result.json << EOF
{
    "table_exists": ${TABLE_EXISTS:-0},
    "columns_match_count": ${COLUMNS_MATCH:-0},
    "procedure_exists": ${PROC_EXISTS:-0},
    "table_data": ${TABLE_DATA_JSON},
    "csv_exists": ${CSV_EXISTS},
    "csv_rows": ${CSV_ROWS},
    "csv_mtime": ${CSV_MTIME},
    "task_start": ${TASK_START},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Export completed. Result file created at /tmp/qa_result.json"
cat /tmp/qa_result.json