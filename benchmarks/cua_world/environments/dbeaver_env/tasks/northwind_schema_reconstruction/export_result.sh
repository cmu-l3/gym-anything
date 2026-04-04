#!/bin/bash
set -e
echo "=== Exporting Northwind Schema Reconstruction Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DB_PATH="/home/ga/Documents/databases/northwind_restored.db"
REPORT_PATH="/home/ga/Documents/exports/restoration_check.csv"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database Existence & Properties
DB_EXISTS="false"
DB_SIZE=0
TABLE_COUNTS="{}"
FK_CHECK="false"
TABLES_FOUND="[]"

if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    DB_SIZE=$(stat -c%s "$DB_PATH" 2>/dev/null || echo "0")
    
    # Introspect the database using sqlite3
    echo "Introspecting database..."
    
    # Get list of tables
    TABLE_LIST=$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table';" | tr '\n' ',' | sed 's/,$//')
    TABLES_FOUND="[\"$(echo "$TABLE_LIST" | sed 's/,/","/g')\"]"
    
    # Count rows in required tables
    # usage of try/catch logic via || echo 0 to handle missing tables
    COUNT_CUSTOMERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM Customers;" 2>/dev/null || echo -1)
    COUNT_PRODUCTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM Products;" 2>/dev/null || echo -1)
    COUNT_ORDERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM Orders;" 2>/dev/null || echo -1)
    COUNT_ITEMS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM OrderItems;" 2>/dev/null || echo -1)
    
    TABLE_COUNTS="{\"Customers\": $COUNT_CUSTOMERS, \"Products\": $COUNT_PRODUCTS, \"Orders\": $COUNT_ORDERS, \"OrderItems\": $COUNT_ITEMS}"

    # Check for Foreign Keys (PRAGMA foreign_key_list)
    # Check if OrderItems has FKs
    FK_COUNT=$(sqlite3 "$DB_PATH" "PRAGMA foreign_key_list(OrderItems);" | wc -l)
    if [ "$FK_COUNT" -ge 2 ]; then
        FK_CHECK="true"
    fi
fi

# 3. Check Report CSV
REPORT_EXISTS="false"
REPORT_VALID="false"
TOP_REVENUE_CUSTOMER=""
REPORT_ROW_COUNT=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    
    # Check creation time
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_VALID="true"
    fi
    
    REPORT_ROW_COUNT=$(wc -l < "$REPORT_PATH")
    
    # Get top customer and revenue (skip header, take first row)
    TOP_REVENUE_CUSTOMER=$(sed -n '2p' "$REPORT_PATH" | cut -d',' -f1)
fi

# 4. Check DBeaver Connection
# Check if a connection named "NorthwindRestored" exists in data-sources.json
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
CONNECTION_CREATED="false"
if [ -f "$CONFIG_DIR/data-sources.json" ]; then
    if grep -qi "NorthwindRestored" "$CONFIG_DIR/data-sources.json"; then
        CONNECTION_CREATED="true"
    fi
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "db_exists": $DB_EXISTS,
    "db_size": $DB_SIZE,
    "tables_found": $TABLES_FOUND,
    "table_counts": $TABLE_COUNTS,
    "fk_integrity_check": $FK_CHECK,
    "report_exists": $REPORT_EXISTS,
    "report_row_count": $REPORT_ROW_COUNT,
    "top_customer": "$TOP_REVENUE_CUSTOMER",
    "connection_created": $CONNECTION_CREATED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="