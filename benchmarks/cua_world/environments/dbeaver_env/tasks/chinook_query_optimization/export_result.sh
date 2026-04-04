#!/bin/bash
# Export script for chinook_query_optimization task

echo "=== Exporting Query Optimization Result ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook_perf.db"
SQL_FILE="/home/ga/Documents/scripts/create_indexes.sql"
REPORT_FILE="/home/ga/Documents/exports/optimization_report.csv"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo 0)

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Verify DBeaver Connection
echo "Checking DBeaver connection..."
CONN_CHECK=$(check_dbeaver_connection "ChinookPerf")
echo "Connection 'ChinookPerf' found: $CONN_CHECK"

# 2. Verify Database Indexes (The Core verification)
# We need to check if indexes exist on specific columns.
# SQLite logic:
#   1. List all indexes for a table: PRAGMA index_list('table_name')
#   2. For each index, get info: PRAGMA index_info('index_name')
#   3. Check if 'name' column in info matches target column

verify_index() {
    local table=$1
    local col=$2
    local found="false"
    
    # Get list of index names for the table
    # PRAGMA index_list output: seq|name|unique|origin|partial
    local indexes=$(sqlite3 "$DB_PATH" "PRAGMA index_list('$table');" | cut -d'|' -f2)
    
    for idx in $indexes; do
        # Get columns for this index
        # PRAGMA index_info output: seqno|cid|name
        # We look for the column name in the 3rd field
        if sqlite3 "$DB_PATH" "PRAGMA index_info('$idx');" | cut -d'|' -f3 | grep -qi "^$col$"; then
            found="true"
            break
        fi
    done
    echo "$found"
}

echo "Verifying indexes..."
IDX_INVOICE_DATE=$(verify_index "invoices" "InvoiceDate")
IDX_CUSTOMER_CITY=$(verify_index "customers" "City")
IDX_TRACK_COMPOSER=$(verify_index "tracks" "Composer")
IDX_TRACK_MILLISECONDS=$(verify_index "tracks" "Milliseconds")

echo "Index status:"
echo "  invoices(InvoiceDate): $IDX_INVOICE_DATE"
echo "  customers(City): $IDX_CUSTOMER_CITY"
echo "  tracks(Composer): $IDX_TRACK_COMPOSER"
echo "  tracks(Milliseconds): $IDX_TRACK_MILLISECONDS"

# 3. Verify Files
echo "Verifying output files..."

# SQL File
SQL_EXISTS="false"
SQL_CONTENT_VALID="false"
if [ -f "$SQL_FILE" ]; then
    SQL_EXISTS="true"
    # Check if created during task
    SQL_MTIME=$(stat -c %Y "$SQL_FILE" 2>/dev/null || echo 0)
    if [ "$SQL_MTIME" -gt "$TASK_START" ]; then
        # Check content loosely for CREATE INDEX
        if grep -qi "CREATE.*INDEX" "$SQL_FILE"; then
            SQL_CONTENT_VALID="true"
        fi
    fi
fi

# Report CSV
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_ROWS=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Check row count (header + 4 rows = 5 lines)
    REPORT_ROWS=$(count_csv_lines "$REPORT_FILE")
    # Check headers
    HEADER=$(head -1 "$REPORT_FILE" | tr '[:upper:]' '[:lower:]')
    if [[ "$HEADER" == *"querynumber"* && "$HEADER" == *"indexname"* ]]; then
        REPORT_VALID="true"
    fi
fi

# 4. Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "connection_exists": $CONN_CHECK,
    "index_invoice_date": $IDX_INVOICE_DATE,
    "index_customer_city": $IDX_CUSTOMER_CITY,
    "index_track_composer": $IDX_TRACK_COMPOSER,
    "index_track_milliseconds": $IDX_TRACK_MILLISECONDS,
    "sql_file_exists": $SQL_EXISTS,
    "sql_content_valid": $SQL_CONTENT_VALID,
    "report_file_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_rows": $REPORT_ROWS,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move and set permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/task_result.json
echo "=== Export Complete ==="