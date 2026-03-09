#!/bin/bash
# Export script for chinook_multicurrency_extension task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Paths
EXTENDED_DB="/home/ga/Documents/databases/chinook_extended.db"
ORIGINAL_DB="/home/ga/Documents/databases/chinook.db"
CSV_PATH="/home/ga/Documents/exports/currency_revenue.csv"
SQL_PATH="/home/ga/Documents/scripts/multicurrency_migration.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 1. Check Files
CSV_EXISTS="false"
CSV_SIZE=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH")
fi

SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# 2. Check Connection Name in DBeaver Config
CONNECTION_FOUND="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Simple grep check for the connection name and path
    if grep -q "ChinookExtended" "$DBEAVER_CONFIG" && grep -q "chinook_extended.db" "$DBEAVER_CONFIG"; then
        CONNECTION_FOUND="true"
    fi
fi

# 3. Check Database State using sqlite3
echo "Inspecting database state..."

# A. Currencies Table
CURRENCY_TABLE_EXISTS="false"
CURRENCY_COUNT=0
if [ -f "$EXTENDED_DB" ]; then
    if sqlite3 "$EXTENDED_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='currencies';" | grep -q "currencies"; then
        CURRENCY_TABLE_EXISTS="true"
        CURRENCY_COUNT=$(sqlite3 "$EXTENDED_DB" "SELECT COUNT(*) FROM currencies;" 2>/dev/null || echo 0)
    fi
fi

# B. Invoices Column
HAS_CURRENCY_COLUMN="false"
if [ -f "$EXTENDED_DB" ]; then
    if sqlite3 "$EXTENDED_DB" "PRAGMA table_info(invoices);" | grep -q "CurrencyCode"; then
        HAS_CURRENCY_COLUMN="true"
    fi
fi

# C. Invoice Data Accuracy
# Check EUR (France etc)
EUR_COUNT=0
EUR_EXPECTED=0
# Check BRL (Brazil)
BRL_COUNT=0
BRL_EXPECTED=0
# Check USD (USA + others)
USD_COUNT=0
NULL_COUNT=0

if [ "$HAS_CURRENCY_COLUMN" = "true" ]; then
    # EUR check (France, Germany, etc.)
    EUR_COUNT=$(sqlite3 "$EXTENDED_DB" "SELECT COUNT(*) FROM invoices WHERE CurrencyCode='EUR';" 2>/dev/null || echo 0)
    EUR_EXPECTED=$(sqlite3 "$EXTENDED_DB" "SELECT COUNT(*) FROM invoices WHERE BillingCountry IN ('France', 'Germany', 'Austria', 'Belgium', 'Finland', 'Ireland', 'Italy', 'Netherlands', 'Portugal', 'Spain');" 2>/dev/null || echo 0)
    
    # BRL check
    BRL_COUNT=$(sqlite3 "$EXTENDED_DB" "SELECT COUNT(*) FROM invoices WHERE CurrencyCode='BRL';" 2>/dev/null || echo 0)
    BRL_EXPECTED=$(sqlite3 "$EXTENDED_DB" "SELECT COUNT(*) FROM invoices WHERE BillingCountry='Brazil';" 2>/dev/null || echo 0)
    
    # Check for NULLs
    NULL_COUNT=$(sqlite3 "$EXTENDED_DB" "SELECT COUNT(*) FROM invoices WHERE CurrencyCode IS NULL;" 2>/dev/null || echo 0)
fi

# D. View Existence and Content
VIEW_EXISTS="false"
VIEW_TOP_CURRENCY=""
VIEW_TOP_REVENUE_USD=0

if [ -f "$EXTENDED_DB" ]; then
    if sqlite3 "$EXTENDED_DB" "SELECT name FROM sqlite_master WHERE type='view' AND name='currency_revenue_summary';" | grep -q "currency_revenue_summary"; then
        VIEW_EXISTS="true"
        # Get top row from view
        VIEW_DATA=$(sqlite3 "$EXTENDED_DB" "SELECT CurrencyCode, TotalRevenueUSD FROM currency_revenue_summary ORDER BY TotalRevenueUSD DESC LIMIT 1;" 2>/dev/null)
        VIEW_TOP_CURRENCY=$(echo "$VIEW_DATA" | cut -d'|' -f1)
        VIEW_TOP_REVENUE_USD=$(echo "$VIEW_DATA" | cut -d'|' -f2)
    fi
fi

# 4. Check Original DB Integrity
ORIGINAL_MODIFIED="false"
INITIAL_CHECKSUM=$(cat /tmp/original_db_checksum 2>/dev/null || echo "")
CURRENT_CHECKSUM=$(md5sum "$ORIGINAL_DB" 2>/dev/null | awk '{print $1}')
if [ "$INITIAL_CHECKSUM" != "$CURRENT_CHECKSUM" ]; then
    ORIGINAL_MODIFIED="true"
fi

# 5. Timestamp checks
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo 0)
CSV_CREATED_DURING_TASK="false"
if [ "$CSV_EXISTS" = "true" ]; then
    CSV_MTIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || echo 0)
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# Create JSON Output
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "sql_exists": $SQL_EXISTS,
    "connection_found": $CONNECTION_FOUND,
    "currency_table_exists": $CURRENCY_TABLE_EXISTS,
    "currency_row_count": $CURRENCY_COUNT,
    "has_currency_column": $HAS_CURRENCY_COLUMN,
    "eur_invoice_count": $EUR_COUNT,
    "eur_expected_count": $EUR_EXPECTED,
    "brl_invoice_count": $BRL_COUNT,
    "brl_expected_count": $BRL_EXPECTED,
    "null_currency_count": $NULL_COUNT,
    "view_exists": $VIEW_EXISTS,
    "view_top_currency": "$VIEW_TOP_CURRENCY",
    "view_top_revenue": "${VIEW_TOP_REVENUE_USD:-0}",
    "original_db_modified": $ORIGINAL_MODIFIED,
    "task_start_time": $TASK_START,
    "task_end_time": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json