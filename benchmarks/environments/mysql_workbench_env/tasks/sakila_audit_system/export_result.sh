#!/bin/bash
# Export script for sakila_audit_system task

echo "=== Exporting Sakila Audit System Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check trigger tr_customer_audit exists
TRIGGER_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM TRIGGERS
    WHERE TRIGGER_SCHEMA='sakila' AND TRIGGER_NAME='tr_customer_audit'
    AND EVENT_OBJECT_TABLE='customer'
" 2>/dev/null)
TRIGGER_EXISTS=${TRIGGER_EXISTS:-0}

# Check trigger timing and event
TRIGGER_TIMING=""
TRIGGER_EVENT=""
if [ "$TRIGGER_EXISTS" -gt 0 ]; then
    TRIGGER_TIMING=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT ACTION_TIMING FROM TRIGGERS
        WHERE TRIGGER_SCHEMA='sakila' AND TRIGGER_NAME='tr_customer_audit'
    " 2>/dev/null)
    TRIGGER_EVENT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT EVENT_MANIPULATION FROM TRIGGERS
        WHERE TRIGGER_SCHEMA='sakila' AND TRIGGER_NAME='tr_customer_audit'
    " 2>/dev/null)
fi
IS_AFTER_UPDATE=0
[ "$TRIGGER_TIMING" = "AFTER" ] && [ "$TRIGGER_EVENT" = "UPDATE" ] && IS_AFTER_UPDATE=1

# Check stored procedure sp_calculate_loyalty_tiers exists
PROC_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM ROUTINES
    WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_NAME='sp_calculate_loyalty_tiers'
    AND ROUTINE_TYPE='PROCEDURE'
" 2>/dev/null)
PROC_EXISTS=${PROC_EXISTS:-0}

# Check customer_audit_log has entries (trigger fired)
AUDIT_LOG_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM customer_audit_log;
" 2>/dev/null)
AUDIT_LOG_COUNT=${AUDIT_LOG_COUNT:-0}

# Check customer_audit_log has entries from distinct customers
AUDIT_DISTINCT_CUSTOMERS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(DISTINCT customer_id) FROM customer_audit_log;
" 2>/dev/null)
AUDIT_DISTINCT_CUSTOMERS=${AUDIT_DISTINCT_CUSTOMERS:-0}

# Check customer_audit_log has required columns and data
AUDIT_HAS_EMAILS=0
if [ "$AUDIT_LOG_COUNT" -gt 0 ]; then
    EMAIL_CHECK=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*) FROM customer_audit_log WHERE old_email IS NOT NULL OR new_email IS NOT NULL;
    " 2>/dev/null)
    [ "${EMAIL_CHECK:-0}" -gt 0 ] && AUDIT_HAS_EMAILS=1
fi

# Check customer_loyalty table has been populated (procedure called)
LOYALTY_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM customer_loyalty;
" 2>/dev/null)
LOYALTY_COUNT=${LOYALTY_COUNT:-0}

# Check tier distribution makes sense
BRONZE_COUNT=0
SILVER_COUNT=0
GOLD_COUNT=0
if [ "$LOYALTY_COUNT" -gt 0 ]; then
    BRONZE_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*) FROM customer_loyalty WHERE tier='Bronze';
    " 2>/dev/null)
    SILVER_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*) FROM customer_loyalty WHERE tier='Silver';
    " 2>/dev/null)
    GOLD_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*) FROM customer_loyalty WHERE tier='Gold';
    " 2>/dev/null)
fi
BRONZE_COUNT=${BRONZE_COUNT:-0}
SILVER_COUNT=${SILVER_COUNT:-0}
GOLD_COUNT=${GOLD_COUNT:-0}

# Check CSV export
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0
OUTPUT_FILE="/home/ga/Documents/exports/customer_loyalty.csv"
if [ -f "$OUTPUT_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

cat > /tmp/audit_system_result.json << EOF
{
    "trigger_exists": $TRIGGER_EXISTS,
    "trigger_is_after_update": $IS_AFTER_UPDATE,
    "proc_exists": $PROC_EXISTS,
    "audit_log_count": $AUDIT_LOG_COUNT,
    "audit_distinct_customers": $AUDIT_DISTINCT_CUSTOMERS,
    "audit_has_emails": $AUDIT_HAS_EMAILS,
    "loyalty_count": $LOYALTY_COUNT,
    "bronze_count": $BRONZE_COUNT,
    "silver_count": $SILVER_COUNT,
    "gold_count": $GOLD_COUNT,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result: trigger=${TRIGGER_EXISTS}(after_update=${IS_AFTER_UPDATE}) proc=${PROC_EXISTS} audit_log=${AUDIT_LOG_COUNT}(distinct=${AUDIT_DISTINCT_CUSTOMERS}) loyalty=${LOYALTY_COUNT}(B=${BRONZE_COUNT}S=${SILVER_COUNT}G=${GOLD_COUNT}) csv=${CSV_EXISTS}(${CSV_ROWS}rows)"
echo "=== Export Complete ==="
