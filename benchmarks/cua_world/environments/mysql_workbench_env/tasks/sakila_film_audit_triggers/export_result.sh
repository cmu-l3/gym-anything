#!/bin/bash
# Export script for sakila_film_audit_triggers task

echo "=== Exporting Sakila Film Audit Triggers Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
MYSQL_CMD="mysql -u root -pGymAnything#2024 -N -e"

# 1. Check if film_audit_log table exists and check columns
TABLE_EXISTS=$($MYSQL_CMD "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='film_audit_log'" 2>/dev/null)
TABLE_EXISTS=${TABLE_EXISTS:-0}

COLUMNS_CHECK=0
if [ "$TABLE_EXISTS" -eq 1 ]; then
    # Check for critical columns: action_type, old_rental_rate, new_rental_rate
    COLS=$($MYSQL_CMD "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='film_audit_log'" 2>/dev/null)
    if echo "$COLS" | grep -q "action_type" && echo "$COLS" | grep -q "old_rental_rate" && echo "$COLS" | grep -q "new_rental_rate"; then
        COLUMNS_CHECK=1
    fi
fi

# 2. Check if Triggers exist
TRG_INSERT_EXISTS=$($MYSQL_CMD "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='sakila' AND EVENT_OBJECT_TABLE='film' AND TRIGGER_NAME='trg_film_after_insert' AND EVENT_MANIPULATION='INSERT' AND ACTION_TIMING='AFTER'" 2>/dev/null)
TRG_UPDATE_EXISTS=$($MYSQL_CMD "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='sakila' AND EVENT_OBJECT_TABLE='film' AND TRIGGER_NAME='trg_film_after_update' AND EVENT_MANIPULATION='UPDATE' AND ACTION_TIMING='AFTER'" 2>/dev/null)
TRG_DELETE_EXISTS=$($MYSQL_CMD "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='sakila' AND EVENT_OBJECT_TABLE='film' AND TRIGGER_NAME='trg_film_after_delete' AND EVENT_MANIPULATION='DELETE' AND ACTION_TIMING='AFTER'" 2>/dev/null)

# 3. Check Audit Log Content (The proof that triggers worked)
# We expect 3 specific rows based on the task description
# Row 1: INSERT of 'AUDIT TEST FILM'
LOG_INSERT_FOUND=$($MYSQL_CMD "SELECT COUNT(*) FROM sakila.film_audit_log WHERE action_type='INSERT' AND title='AUDIT TEST FILM'" 2>/dev/null)

# Row 2: UPDATE of film_id=1, old 0.99 -> new 1.99
LOG_UPDATE_FOUND=$($MYSQL_CMD "SELECT COUNT(*) FROM sakila.film_audit_log WHERE action_type='UPDATE' AND film_id=1 AND old_rental_rate=0.99 AND new_rental_rate=1.99" 2>/dev/null)

# Row 3: DELETE of 'AUDIT TEST FILM'
LOG_DELETE_FOUND=$($MYSQL_CMD "SELECT COUNT(*) FROM sakila.film_audit_log WHERE action_type='DELETE' AND title='AUDIT TEST FILM'" 2>/dev/null)

# 4. Check Side Effects on Data
# Film 1 should be 1.99
FILM_1_RATE=$($MYSQL_CMD "SELECT rental_rate FROM sakila.film WHERE film_id=1" 2>/dev/null)
# 'AUDIT TEST FILM' should be gone
TEST_FILM_EXISTS=$($MYSQL_CMD "SELECT COUNT(*) FROM sakila.film WHERE title='AUDIT TEST FILM'" 2>/dev/null)

# 5. Check CSV Export
CSV_FILE="/home/ga/Documents/exports/film_audit_log.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$CSV_FILE" 2>/dev/null || echo "0")
    # Count non-empty lines
    CSV_ROWS=$(grep -cve '^\s*$' "$CSV_FILE" 2>/dev/null || echo "0")
fi

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "table_exists": ${TABLE_EXISTS:-0},
    "columns_check": ${COLUMNS_CHECK:-0},
    "trg_insert_exists": ${TRG_INSERT_EXISTS:-0},
    "trg_update_exists": ${TRG_UPDATE_EXISTS:-0},
    "trg_delete_exists": ${TRG_DELETE_EXISTS:-0},
    "log_insert_found": ${LOG_INSERT_FOUND:-0},
    "log_update_found": ${LOG_UPDATE_FOUND:-0},
    "log_delete_found": ${LOG_DELETE_FOUND:-0},
    "film_1_rate": "${FILM_1_RATE:-0}",
    "test_film_exists": ${TEST_FILM_EXISTS:-0},
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json