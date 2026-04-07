#!/bin/bash
# Export script for sakila_customer_location_history task

echo "=== Exporting Sakila Customer Location History Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
DB_USER="root"
DB_PASS="GymAnything#2024"
DB_NAME="sakila"

# 1. Check Table Structure
echo "Checking table structure..."
TABLE_EXISTS=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema='$DB_NAME' AND table_name='customer_address_history';
" 2>/dev/null)
TABLE_EXISTS=${TABLE_EXISTS:-0}

COLUMNS_CHECK=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "
    SELECT COUNT(*) FROM information_schema.columns 
    WHERE table_schema='$DB_NAME' AND table_name='customer_address_history' 
    AND column_name IN ('valid_from', 'valid_to', 'history_id');
" 2>/dev/null)
COLUMNS_CHECK=${COLUMNS_CHECK:-0}

# 2. Check Backfill Status
echo "Checking backfill..."
HISTORY_COUNT=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "SELECT COUNT(*) FROM customer_address_history;" 2>/dev/null)
HISTORY_COUNT=${HISTORY_COUNT:-0}
INITIAL_CUSTOMER_COUNT=$(cat /tmp/initial_customer_count 2>/dev/null || echo "599")

# 3. Check Trigger Existence
echo "Checking trigger..."
TRIGGER_EXISTS=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "
    SELECT COUNT(*) FROM information_schema.triggers 
    WHERE trigger_schema='$DB_NAME' AND trigger_name='trg_track_address_changes';
" 2>/dev/null)
TRIGGER_EXISTS=${TRIGGER_EXISTS:-0}

# 4. Check Manual Test (Mary Smith - ID 1)
# She should have at least 2 records: one current (valid_to IS NULL) and one historical
MARY_HISTORY_COUNT=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "
    SELECT COUNT(*) FROM customer_address_history WHERE customer_id = 1;
" 2>/dev/null)
MARY_HISTORY_COUNT=${MARY_HISTORY_COUNT:-0}

MARY_CURRENT_ADDRESS=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "
    SELECT address_id FROM customer WHERE customer_id = 1;
" 2>/dev/null)

# 5. Automated Verification of Trigger Logic (Anti-Gaming)
# We will perform an update on a DIFFERENT customer (ID 100) and verify history is created.
echo "Running automated verification..."
VERIFY_TEST_PASSED="false"

if [ "$TRIGGER_EXISTS" -eq "1" ] && [ "$TABLE_EXISTS" -eq "1" ]; then
    # Pick customer 100, get current address
    C100_OLD_ADDR=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "SELECT address_id FROM customer WHERE customer_id = 100")
    
    # Change address to something else (e.g., 50)
    mysql -u $DB_USER -p$DB_PASS $DB_NAME -e "UPDATE customer SET address_id = 50 WHERE customer_id = 100" 2>/dev/null
    
    # Check history table for logic:
    # 1. Should have a record with valid_to IS NOT NULL (the old record)
    # 2. Should have a record with valid_to IS NULL (the new record)
    # 3. Total records for ID 100 should be >= 2
    
    C100_HISTORY_COUNT=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "SELECT COUNT(*) FROM customer_address_history WHERE customer_id = 100")
    C100_ACTIVE_COUNT=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "SELECT COUNT(*) FROM customer_address_history WHERE customer_id = 100 AND valid_to IS NULL")
    C100_CLOSED_COUNT=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "SELECT COUNT(*) FROM customer_address_history WHERE customer_id = 100 AND valid_to IS NOT NULL")
    
    if [ "$C100_HISTORY_COUNT" -ge 2 ] && [ "$C100_ACTIVE_COUNT" -eq 1 ] && [ "$C100_CLOSED_COUNT" -ge 1 ]; then
        VERIFY_TEST_PASSED="true"
    fi
    
    # Reset ID 100 for cleanliness (optional)
    mysql -u $DB_USER -p$DB_PASS $DB_NAME -e "UPDATE customer SET address_id = $C100_OLD_ADDR WHERE customer_id = 100" 2>/dev/null
fi

# 6. Check CSV Export
OUTPUT_FILE="/home/ga/Documents/exports/mary_smith_history.csv"
CSV_EXISTS="false"
CSV_ROWS=0
if [ -f "$OUTPUT_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    # Check that it was created AFTER task start
    if [ "$CSV_MTIME" -lt "$TASK_START" ]; then
        CSV_EXISTS="false" # Disqualify old files
    fi
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1)) # Subtract header
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

# Compile Result JSON
cat > /tmp/scd2_result.json << EOF
{
    "table_exists": $TABLE_EXISTS,
    "columns_check": $COLUMNS_CHECK,
    "backfill_count": $HISTORY_COUNT,
    "trigger_exists": $TRIGGER_EXISTS,
    "mary_history_count": $MARY_HISTORY_COUNT,
    "mary_current_address": $MARY_CURRENT_ADDRESS,
    "automated_verify_passed": $VERIFY_TEST_PASSED,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/scd2_result.json"
cat /tmp/scd2_result.json
echo "=== Export Complete ==="