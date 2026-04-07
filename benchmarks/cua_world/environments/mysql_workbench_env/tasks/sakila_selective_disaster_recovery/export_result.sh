#!/bin/bash
# Export script for sakila_selective_disaster_recovery

echo "=== Exporting Disaster Recovery Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_ROWS=$(cat /tmp/initial_row_count 2>/dev/null || echo "0")

# 3. Verify Database State
# Metric A: Does the audit_tag column still exist?
HAS_AUDIT_COLUMN=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='payment' AND COLUMN_NAME='audit_tag';
")

# Metric B: Total Row Count (Should be ~16049 if fully restored)
FINAL_ROW_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM payment;")

# Metric C: Restored Rows Integrity
# Check how many rows in the gap period exist and have audit_tag='RESTORED'
RESTORED_CORRECTLY_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM payment 
    WHERE payment_date >= '2005-05-25 00:00:00' 
      AND payment_date <= '2005-05-28 23:59:59'
      AND audit_tag = 'RESTORED';
")

# Metric D: Gap Rows present but WRONG tag (e.g., NULL or default)
RESTORED_WRONG_TAG_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM payment 
    WHERE payment_date >= '2005-05-25 00:00:00' 
      AND payment_date <= '2005-05-28 23:59:59'
      AND (audit_tag != 'RESTORED' OR audit_tag IS NULL);
")

# Metric E: Data Safety (Did we overwrite existing 'verified' tags?)
# We check a random sample of rows outside the gap that should be 'verified'
# payment_id 10 is outside the gap (payment_date is 2005-05-25 11:30:37 which IS in gap? wait.
# Let's check ID 1. ID 1 date is 2005-05-25 11:30:37.
# Let's pick a date definitely outside gap.
# The gap is May 25-28.
# Payment ID 16049 is usually Aug 2005. 
# Let's check preservation of non-gap data.
EXISTING_DATA_PRESERVED=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM payment 
    WHERE audit_tag IN ('original', 'verified') 
    AND (payment_date < '2005-05-25' OR payment_date > '2005-05-28 23:59:59');
")

# 4. Check for Staging Database (Evidence of correct process)
STAGING_DB_EXISTS=$(mysql -u root -p'GymAnything#2024' -N -e "SHOW DATABASES LIKE '%stage%';")
if [ -n "$STAGING_DB_EXISTS" ]; then STAGING_USED="true"; else STAGING_USED="false"; fi

# 5. Check Export CSV
CSV_PATH="/home/ga/Documents/exports/restored_payments.csv"
CSV_EXISTS="false"
CSV_ROWS=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -lt "$TASK_START" ]; then
        CSV_EXISTS="false" # Created before task started
    fi
    CSV_ROWS=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
fi

# 6. Generate Result JSON
cat > /tmp/disaster_recovery_result.json << EOF
{
    "has_audit_column": $([ "$HAS_AUDIT_COLUMN" -eq 1 ] && echo "true" || echo "false"),
    "final_row_count": ${FINAL_ROW_COUNT:-0},
    "initial_row_count": ${INITIAL_ROWS:-0},
    "restored_correctly_count": ${RESTORED_CORRECTLY_COUNT:-0},
    "restored_wrong_tag_count": ${RESTORED_WRONG_TAG_COUNT:-0},
    "existing_data_preserved_count": ${EXISTING_DATA_PRESERVED:-0},
    "staging_db_detected": $STAGING_USED,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "task_start_time": $TASK_START,
    "export_time": $(date +%s)
}
EOF

# Set permissions
chmod 666 /tmp/disaster_recovery_result.json

echo "Export complete. Result:"
cat /tmp/disaster_recovery_result.json