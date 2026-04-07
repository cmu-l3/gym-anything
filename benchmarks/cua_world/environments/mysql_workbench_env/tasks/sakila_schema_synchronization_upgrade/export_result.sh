#!/bin/bash
# Export script for sakila_schema_synchronization_upgrade task

echo "=== Exporting Schema Synchronization Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Verify Schema Changes in 'sakila' (Production)

# Check Column: customer.loyalty_tier
HAS_LOYALTY=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM COLUMNS 
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='customer' AND COLUMN_NAME='loyalty_tier'
")

# Check Column: film.streaming_url
HAS_STREAMING=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM COLUMNS 
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='film' AND COLUMN_NAME='streaming_url'
")

# Check Table: rental_audit_log
HAS_AUDIT_TABLE=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM TABLES 
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='rental_audit_log'
")

# Check Index: payment.idx_payment_date_amount
HAS_INDEX=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM STATISTICS 
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='payment' AND INDEX_NAME='idx_payment_date_amount'
")

# 2. Verify Data Preservation (Critical)
# If the agent used DROP TABLE + CREATE TABLE, the data will be gone or significantly reduced (if they tried to re-insert only some).
FINAL_CUST_COUNT=$(sakila_query "SELECT COUNT(*) FROM customer")
FINAL_FILM_COUNT=$(sakila_query "SELECT COUNT(*) FROM film")

INITIAL_CUST_COUNT=$(cat /tmp/initial_cust_count 2>/dev/null || echo "599")
INITIAL_FILM_COUNT=$(cat /tmp/initial_film_count 2>/dev/null || echo "1000")

# Allow small tolerance? No, structural migration shouldn't lose any rows.
DATA_PRESERVED="false"
if [ "$FINAL_CUST_COUNT" -ge "$INITIAL_CUST_COUNT" ] && [ "$FINAL_FILM_COUNT" -ge "$INITIAL_FILM_COUNT" ]; then
    DATA_PRESERVED="true"
fi

# 3. Verify Migration Artifact
SCRIPT_PATH="/home/ga/Documents/exports/migration_v2.sql"
SCRIPT_EXISTS="false"
SCRIPT_CONTENT_VALID="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    # Check for keywords
    if grep -qi "ALTER TABLE" "$SCRIPT_PATH" || grep -qi "CREATE TABLE" "$SCRIPT_PATH"; then
        SCRIPT_CONTENT_VALID="true"
    fi
fi

# Export results to JSON
cat > /tmp/migration_result.json << EOF
{
    "has_loyalty_column": ${HAS_LOYALTY:-0},
    "has_streaming_column": ${HAS_STREAMING:-0},
    "has_audit_table": ${HAS_AUDIT_TABLE:-0},
    "has_payment_index": ${HAS_INDEX:-0},
    "final_customer_count": ${FINAL_CUST_COUNT:-0},
    "final_film_count": ${FINAL_FILM_COUNT:-0},
    "initial_customer_count": ${INITIAL_CUST_COUNT:-0},
    "data_preserved": $DATA_PRESERVED,
    "script_exists": $SCRIPT_EXISTS,
    "script_content_valid": $SCRIPT_CONTENT_VALID,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result: loyalty=${HAS_LOYALTY} streaming=${HAS_STREAMING} audit=${HAS_AUDIT_TABLE} idx=${HAS_INDEX} data_preserved=${DATA_PRESERVED}"
echo "=== Export Complete ==="