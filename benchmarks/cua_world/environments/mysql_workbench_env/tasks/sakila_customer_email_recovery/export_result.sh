#!/bin/bash
# Export script for sakila_customer_email_recovery task

echo "=== Exporting Sakila Customer Email Recovery Result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPORT_FILE="/home/ga/Documents/exports/recovered_emails.csv"

# 1. Verify Database State
echo "Verifying database state..."

# Check 1: Are there any NULL emails left? (Should be 0)
NULL_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer WHERE email IS NULL;")

# Check 2: Verify Store 1 integrity (Anti-gaming)
# Store 1 emails should NOT be NULL and should match standard pattern
STORE1_NULLS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer WHERE store_id = 1 AND email IS NULL;")
STORE1_INVALID=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM customer 
    WHERE store_id = 1 
    AND email NOT REGEXP '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$';
")

# Check 3: Verify Data Accuracy for Store 2
# We check if the emails follow the Sakila pattern (First.Last@sakilacustomer.org)
# This is a robust check without needing the original list, as we know the generation rule.
STORE2_ACCURACY_FAILURES=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM customer 
    WHERE store_id = 2 
    AND email != CONCAT(first_name, '.', last_name, '@sakilacustomer.org');
")

# 2. Verify Output File
CSV_EXISTS="false"
CSV_ROWS=0
CSV_CREATED_DURING_TASK="false"

if [ -f "$EXPORT_FILE" ]; then
    CSV_EXISTS="true"
    # Check rows (excluding header)
    CSV_ROWS=$(($(wc -l < "$EXPORT_FILE") - 1))
    
    # Check creation time
    FILE_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check for Staging Table (Optional but good evidence)
# Agent might name it anything, but we look for likely candidates or recent tables
STAGING_TABLE_CANDIDATES=$(mysql -u root -p'GymAnything#2024' -N -e "
    SELECT TABLE_NAME FROM information_schema.TABLES 
    WHERE TABLE_SCHEMA = 'sakila' 
    AND CREATE_TIME > FROM_UNIXTIME($TASK_START)
    AND TABLE_NAME != 'customer';
")
STAGING_CREATED="false"
if [ -n "$STAGING_TABLE_CANDIDATES" ]; then
    STAGING_CREATED="true"
fi

# 4. Generate Result JSON
cat > /tmp/recovery_result.json << EOF
{
    "null_emails_remaining": ${NULL_COUNT:-999},
    "store1_nulls": ${STORE1_NULLS:-999},
    "store1_invalid_format": ${STORE1_INVALID:-999},
    "store2_accuracy_failures": ${STORE2_ACCURACY_FAILURES:-999},
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "staging_table_detected": $STAGING_CREATED,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result generated at /tmp/recovery_result.json"
cat /tmp/recovery_result.json