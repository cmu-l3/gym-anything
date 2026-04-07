#!/bin/bash
# Export script for sakila_stored_procedure_debugging task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check Exports
check_file() {
    local f=$1
    if [ -f "$f" ]; then
        local mtime=$(stat -c%Y "$f" 2>/dev/null || echo "0")
        local lines=$(wc -l < "$f" 2>/dev/null || echo "0")
        echo "{\"exists\": true, \"mtime\": $mtime, \"lines\": $lines}"
    else
        echo "{\"exists\": false, \"mtime\": 0, \"lines\": 0}"
    fi
}

FILE_SALES=$(check_file "/home/ga/Documents/exports/sales_by_category.csv")
FILE_DEAD=$(check_file "/home/ga/Documents/exports/dead_inventory.csv")
FILE_CREDIT=$(check_file "/home/ga/Documents/exports/top_credit_customers.csv")

# 2. Check Database State Programmatically

# Check if credit_score column exists
COL_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM COLUMNS 
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='customer' AND COLUMN_NAME='credit_score'
")

# Check if sp_report_sales_by_category runs without error
# We try to call it. If it fails (due to group by), output will be empty/error
SALES_PROC_STATUS="fail"
mysql -u root -p'GymAnything#2024' sakila -e "CALL sp_report_sales_by_category();" > /tmp/sales_test.txt 2>&1
if [ $? -eq 0 ]; then
    SALES_PROC_STATUS="pass"
fi

# Check if sp_identify_dead_inventory returns rows (logic fix)
DEAD_PROC_ROWS=0
mysql -u root -p'GymAnything#2024' sakila -e "CALL sp_identify_dead_inventory();" > /tmp/dead_test.txt 2>&1
if [ $? -eq 0 ]; then
    # Count rows (minus header)
    DEAD_PROC_ROWS=$(($(wc -l < /tmp/dead_test.txt) - 1))
    [ $DEAD_PROC_ROWS -lt 0 ] && DEAD_PROC_ROWS=0
fi

# Check if sp_calculate_customer_credit runs (implies column exists)
CREDIT_PROC_STATUS="fail"
mysql -u root -p'GymAnything#2024' sakila -e "CALL sp_calculate_customer_credit();" > /tmp/credit_test.txt 2>&1
if [ $? -eq 0 ]; then
    CREDIT_PROC_STATUS="pass"
fi

# Check if credit_score actually has data
CREDIT_DATA_COUNT=0
if [ "$COL_EXISTS" -gt 0 ]; then
    CREDIT_DATA_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer WHERE credit_score > 0")
fi

# Construct JSON result
cat > /tmp/debugging_result.json << EOF
{
    "task_start": $TASK_START,
    "file_sales": $FILE_SALES,
    "file_dead": $FILE_DEAD,
    "file_credit": $FILE_CREDIT,
    "col_credit_score_exists": $COL_EXISTS,
    "sales_proc_status": "$SALES_PROC_STATUS",
    "dead_proc_rows": $DEAD_PROC_ROWS,
    "credit_proc_status": "$CREDIT_PROC_STATUS",
    "credit_data_populated_count": $CREDIT_DATA_COUNT
}
EOF

echo "Result generated at /tmp/debugging_result.json"
cat /tmp/debugging_result.json
echo "=== Export Complete ==="