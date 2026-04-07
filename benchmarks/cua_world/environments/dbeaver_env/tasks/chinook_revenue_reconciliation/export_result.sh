#!/bin/bash
# Export script for chinook_revenue_reconciliation task
# Collects database state, file existence, and verification metrics

echo "=== Collecting Revenue Reconciliation Results ==="

source /workspace/scripts/task_utils.sh

LEDGER_DB="/home/ga/Documents/databases/chinook_ledger.db"
EXPORT_CSV="/home/ga/Documents/exports/correction_report.csv"
SCRIPT_FILE="/home/ga/Documents/scripts/reconciliation.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo 0)

take_screenshot /tmp/task_final.png

# --- Check DBeaver connection ---
CONN_FOUND=false
if [ -f "$DBEAVER_CONFIG" ]; then
    if grep -qi "LedgerAudit" "$DBEAVER_CONFIG" 2>/dev/null; then
        CONN_FOUND=true
    fi
fi

# --- Check database state ---
INVOICE_ITEMS_COUNT=-1
NEGATIVE_INVOICES=-1
DISCREPANT_MONTH_COUNT=-1
DISCREPANT_MONTHS=""
Q4_TOTAL_MISMATCHES=-1
CORRECTION_LOG_EXISTS=false
CORRECTION_LOG_ROWS=0
DB_EXISTS=false

if [ -f "$LEDGER_DB" ]; then
    DB_EXISTS=true

    # Count invoice_items (should be 2240 after fix)
    INVOICE_ITEMS_COUNT=$(sqlite3 "$LEDGER_DB" \
        "SELECT COUNT(*) FROM invoice_items" 2>/dev/null || echo -1)

    # Count negative invoices (should be 0 after fix)
    NEGATIVE_INVOICES=$(sqlite3 "$LEDGER_DB" \
        "SELECT COUNT(*) FROM invoices WHERE Total < 0" 2>/dev/null || echo -1)

    # Count months where GL doesn't match actual revenue
    DISCREPANT_MONTH_COUNT=$(sqlite3 "$LEDGER_DB" "
        SELECT COUNT(*)
        FROM general_ledger gl
        LEFT JOIN (
            SELECT strftime('%Y-%m', InvoiceDate) AS ym, ROUND(SUM(Total), 2) AS rev
            FROM invoices GROUP BY ym
        ) act ON gl.YearMonth = act.ym
        WHERE ROUND(ABS(gl.Revenue - COALESCE(act.rev, 0)), 2) > 0.01
    " 2>/dev/null || echo -1)

    # Get list of discrepant months
    DISCREPANT_MONTHS=$(sqlite3 "$LEDGER_DB" "
        SELECT GROUP_CONCAT(gl.YearMonth, ',')
        FROM general_ledger gl
        LEFT JOIN (
            SELECT strftime('%Y-%m', InvoiceDate) AS ym, ROUND(SUM(Total), 2) AS rev
            FROM invoices GROUP BY ym
        ) act ON gl.YearMonth = act.ym
        WHERE ROUND(ABS(gl.Revenue - COALESCE(act.rev, 0)), 2) > 0.01
    " 2>/dev/null || echo "")

    # Count Q4 2013 invoices where Total != SUM(items)
    Q4_TOTAL_MISMATCHES=$(sqlite3 "$LEDGER_DB" "
        SELECT COUNT(*)
        FROM invoices i
        WHERE i.InvoiceDate >= '2013-10-01' AND i.InvoiceDate < '2014-01-01'
          AND ROUND(ABS(i.Total - (
              SELECT COALESCE(SUM(ii.UnitPrice * ii.Quantity), 0)
              FROM invoice_items ii WHERE ii.InvoiceId = i.InvoiceId
          )), 2) > 0.01
    " 2>/dev/null || echo -1)

    # Check correction_log table
    CL_TABLE=$(sqlite3 "$LEDGER_DB" \
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='correction_log'" \
        2>/dev/null || echo 0)
    if [ "$CL_TABLE" = "1" ]; then
        CORRECTION_LOG_EXISTS=true
        CORRECTION_LOG_ROWS=$(sqlite3 "$LEDGER_DB" \
            "SELECT COUNT(*) FROM correction_log" 2>/dev/null || echo 0)
    fi
fi

# --- Check CSV export ---
CSV_EXISTS=false
CSV_CREATED_DURING_TASK=false
CSV_ROW_COUNT=0
CSV_SIZE=0
if [ -f "$EXPORT_CSV" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c%s "$EXPORT_CSV" 2>/dev/null || echo 0)
    CSV_ROW_COUNT=$(wc -l < "$EXPORT_CSV" 2>/dev/null || echo 0)
    FILE_TIME=$(stat -c%Y "$EXPORT_CSV" 2>/dev/null || echo 0)
    if [ "$FILE_TIME" -gt "$START_TIME" ]; then
        CSV_CREATED_DURING_TASK=true
    fi
fi

# --- Check SQL script ---
SCRIPT_EXISTS=false
SCRIPT_SIZE=0
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS=true
    SCRIPT_SIZE=$(stat -c%s "$SCRIPT_FILE" 2>/dev/null || echo 0)
fi

# --- Check DBeaver running ---
APP_RUNNING=false
if pgrep -f "dbeaver" > /dev/null 2>&1; then
    APP_RUNNING=true
fi

# --- Check ground truth exists ---
GT_EXISTS=false
if [ -f /tmp/reconciliation_ground_truth.json ]; then
    GT_EXISTS=true
fi

# --- Write result JSON ---
TEMP=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP" << ENDJSON
{
    "task_start": $START_TIME,
    "db_exists": $DB_EXISTS,
    "connection_found": $CONN_FOUND,
    "invoice_items_count": $INVOICE_ITEMS_COUNT,
    "negative_invoices_count": $NEGATIVE_INVOICES,
    "discrepant_month_count": $DISCREPANT_MONTH_COUNT,
    "discrepant_months": "$DISCREPANT_MONTHS",
    "q4_total_mismatches": $Q4_TOTAL_MISMATCHES,
    "correction_log_exists": $CORRECTION_LOG_EXISTS,
    "correction_log_rows": $CORRECTION_LOG_ROWS,
    "csv_export": {
        "exists": $CSV_EXISTS,
        "created_during_task": $CSV_CREATED_DURING_TASK,
        "row_count": $CSV_ROW_COUNT,
        "size_bytes": $CSV_SIZE,
        "path": "$EXPORT_CSV"
    },
    "sql_script": {
        "exists": $SCRIPT_EXISTS,
        "size_bytes": $SCRIPT_SIZE,
        "path": "$SCRIPT_FILE"
    },
    "app_running": $APP_RUNNING,
    "ground_truth_exists": $GT_EXISTS,
    "ground_truth_path": "/tmp/reconciliation_ground_truth.json"
}
ENDJSON

rm -f /tmp/reconciliation_result.json 2>/dev/null || true
cp "$TEMP" /tmp/reconciliation_result.json
chmod 666 /tmp/reconciliation_result.json 2>/dev/null || true

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

rm -f "$TEMP"

echo "Result:"
cat /tmp/reconciliation_result.json
echo ""
echo "=== Results collected ==="
