#!/bin/bash
# Export script for chinook_customer_vertical_partitioning task
# Introspects the SQLite database to verify schema changes

echo "=== Exporting Vertical Partitioning Result ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook_refactor.db"
EXPORT_CSV="/home/ga/Documents/exports/refactored_customers.csv"
SCRIPT_SQL="/home/ga/Documents/scripts/partitioning.sql"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Database Introspection ---

DB_EXISTS="false"
CUSTOMERS_SCHEMA=""
CONTACT_SCHEMA=""
VIEW_SCHEMA=""
CUSTOMERS_ROWS=0
CONTACT_ROWS=0
VIEW_ROWS=0
SAMPLE_DATA_CHECK="false"
ORPHAN_CHECK=0

if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    
    # Get Schemas
    CUSTOMERS_SCHEMA=$(sqlite3 "$DB_PATH" ".schema customers" | tr '\n' ' ' | sed 's/"/\\"/g')
    CONTACT_SCHEMA=$(sqlite3 "$DB_PATH" ".schema customer_contact" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')
    VIEW_SCHEMA=$(sqlite3 "$DB_PATH" ".schema v_customers_extended" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')
    
    # Count Rows
    CUSTOMERS_ROWS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM customers;" 2>/dev/null || echo -1)
    CONTACT_ROWS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM customer_contact;" 2>/dev/null || echo -1)
    VIEW_ROWS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM v_customers_extended;" 2>/dev/null || echo -1)
    
    # Verify Data Integrity (Sample Check)
    # Check if Customer 1 (Luís Gonçalves) has correct Email in the new table/view
    # and if we can join them.
    SAMPLE_EMAIL=$(sqlite3 "$DB_PATH" "SELECT Email FROM customer_contact WHERE CustomerId=1;" 2>/dev/null)
    if [ "$SAMPLE_EMAIL" == "luisg@embraer.com.br" ]; then
        SAMPLE_DATA_CHECK="true"
    fi
    
    # Check for orphans (ids in contact not in customers)
    ORPHAN_CHECK=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM customer_contact WHERE CustomerId NOT IN (SELECT CustomerId FROM customers);" 2>/dev/null || echo 0)
fi

# --- File Artifact Checks ---

CSV_EXISTS="false"
CSV_SIZE=0
CSV_ROWS=0
if [ -f "$EXPORT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$EXPORT_CSV" 2>/dev/null || echo 0)
    # Subtract header
    TOTAL_LINES=$(wc -l < "$EXPORT_CSV")
    CSV_ROWS=$((TOTAL_LINES - 1))
fi

SQL_EXISTS="false"
if [ -f "$SCRIPT_SQL" ]; then
    SQL_EXISTS="true"
fi

# --- DBeaver Connection Check ---
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
CONN_FOUND="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Simple check for connection name
    if grep -qi "ChinookRefactor" "$DBEAVER_CONFIG"; then
        CONN_FOUND="true"
    fi
fi

# --- Construct Result JSON ---
# Using python to write JSON safely avoids shell quoting hell with schema strings
python3 -c "
import json
import os

result = {
    'db_exists': $DB_EXISTS,
    'customers_schema': \"$CUSTOMERS_SCHEMA\",
    'contact_schema': \"$CONTACT_SCHEMA\",
    'view_schema': \"$VIEW_SCHEMA\",
    'customers_rows': $CUSTOMERS_ROWS,
    'contact_rows': $CONTACT_ROWS,
    'view_rows': $VIEW_ROWS,
    'sample_data_valid': $SAMPLE_DATA_CHECK,
    'orphan_count': $ORPHAN_CHECK,
    'csv_exists': $CSV_EXISTS,
    'csv_rows': $CSV_ROWS,
    'sql_exists': $SQL_EXISTS,
    'connection_found': $CONN_FOUND,
    'task_timestamp': $TASK_START
}

with open('/tmp/partition_result.json', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 /tmp/partition_result.json 2>/dev/null || true

echo "Result generated at /tmp/partition_result.json"
cat /tmp/partition_result.json
echo "=== Export complete ==="