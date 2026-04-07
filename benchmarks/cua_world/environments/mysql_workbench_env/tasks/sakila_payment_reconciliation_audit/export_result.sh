#!/bin/bash
# Export script for sakila_payment_reconciliation_audit task

echo "=== Exporting Payment Reconciliation Audit Results ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

run_sql() {
    mysql -u root -p'GymAnything#2024' -N -e "$1" 2>/dev/null || echo ""
}

run_sql_sakila() {
    mysql -u root -p'GymAnything#2024' sakila -N -e "$1" 2>/dev/null || echo ""
}

# ---- 1. Check staging table: processor_transactions ----
PT_EXISTS=$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='processor_transactions'")
PT_EXISTS=${PT_EXISTS:-0}
PT_ROWS=0
PT_COLS=0
if [ "$PT_EXISTS" -ge 1 ]; then
    PT_ROWS=$(run_sql_sakila "SELECT COUNT(*) FROM processor_transactions")
    PT_ROWS=${PT_ROWS:-0}
    PT_COLS=$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='processor_transactions'")
    PT_COLS=${PT_COLS:-0}
fi

# ---- 2. Check reconciliation view ----
VIEW_EXISTS=$(run_sql "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_payment_reconciliation'")
VIEW_EXISTS=${VIEW_EXISTS:-0}

# Get per-category counts from the view
RECON_COUNTS_JSON="{}"
RECON_TOTAL_ROWS=0
if [ "$VIEW_EXISTS" -ge 1 ]; then
    RECON_TOTAL_ROWS=$(run_sql_sakila "SELECT COUNT(*) FROM v_payment_reconciliation")
    RECON_TOTAL_ROWS=${RECON_TOTAL_ROWS:-0}

    RECON_COUNTS_JSON=$(python3 -c "
import pymysql, json
try:
    conn = pymysql.connect(host='localhost', user='root', password='GymAnything#2024', database='sakila')
    cur = conn.cursor()
    cur.execute('SELECT match_status, COUNT(*) FROM v_payment_reconciliation GROUP BY match_status')
    counts = {}
    for status, cnt in cur.fetchall():
        counts[str(status)] = int(cnt)
    print(json.dumps(counts))
    conn.close()
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)
    RECON_COUNTS_JSON=${RECON_COUNTS_JSON:-"{}"}
fi

# ---- 3. Check summary table ----
SUMMARY_EXISTS=$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='reconciliation_summary'")
SUMMARY_EXISTS=${SUMMARY_EXISTS:-0}
SUMMARY_ROWS=0
SUMMARY_NET=0
SUMMARY_JSON="{}"
if [ "$SUMMARY_EXISTS" -ge 1 ]; then
    SUMMARY_ROWS=$(run_sql_sakila "SELECT COUNT(*) FROM reconciliation_summary")
    SUMMARY_ROWS=${SUMMARY_ROWS:-0}

    SUMMARY_JSON=$(python3 -c "
import pymysql, json
try:
    conn = pymysql.connect(host='localhost', user='root', password='GymAnything#2024', database='sakila')
    cur = conn.cursor(pymysql.cursors.DictCursor)
    cur.execute('SELECT * FROM reconciliation_summary')
    rows = cur.fetchall()
    # Convert Decimal to float for JSON serialization
    for r in rows:
        for k, v in r.items():
            if hasattr(v, 'is_finite'):
                r[k] = float(v)
    print(json.dumps(rows, default=str))
    conn.close()
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)
    SUMMARY_JSON=${SUMMARY_JSON:-"{}"}
fi

# ---- 4. Check corrections procedure + audit table ----
PROC_EXISTS=$(run_sql "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_NAME='sp_apply_corrections'")
PROC_EXISTS=${PROC_EXISTS:-0}

AUDIT_EXISTS=$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='audit_corrections'")
AUDIT_EXISTS=${AUDIT_EXISTS:-0}
AUDIT_ROWS=0
if [ "$AUDIT_EXISTS" -ge 1 ]; then
    AUDIT_ROWS=$(run_sql_sakila "SELECT COUNT(*) FROM audit_corrections")
    AUDIT_ROWS=${AUDIT_ROWS:-0}
fi

# ---- 5. Check CSV exports ----
RECON_CSV="/home/ga/Documents/exports/reconciliation_report.csv"
SUMMARY_CSV="/home/ga/Documents/exports/reconciliation_summary.csv"

check_csv() {
    local filepath="$1"
    local exists="false"
    local rows=0
    local size=0
    local recent="false"
    if [ -f "$filepath" ]; then
        exists="true"
        size=$(stat -c%s "$filepath" 2>/dev/null || echo "0")
        rows=$(wc -l < "$filepath" 2>/dev/null || echo "0")
        rows=$((rows - 1))  # subtract header
        local mtime=$(stat -c%Y "$filepath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            recent="true"
        fi
    fi
    echo "{\"exists\": $exists, \"rows\": $rows, \"size\": $size, \"recent\": $recent}"
}

RECON_CSV_JSON=$(check_csv "$RECON_CSV")
SUMMARY_CSV_JSON=$(check_csv "$SUMMARY_CSV")

# ---- 6. App running check ----
APP_RUNNING="false"
if pgrep -f "mysql-workbench" > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# ---- Construct result JSON ----
cat > /tmp/task_result.json << ENDJSON
{
    "staging_table": {
        "exists": $PT_EXISTS,
        "rows": $PT_ROWS,
        "cols": $PT_COLS
    },
    "recon_view": {
        "exists": $VIEW_EXISTS,
        "total_rows": $RECON_TOTAL_ROWS,
        "counts": $RECON_COUNTS_JSON
    },
    "summary_table": {
        "exists": $SUMMARY_EXISTS,
        "rows": $SUMMARY_ROWS,
        "data": $SUMMARY_JSON
    },
    "corrections": {
        "proc_exists": $PROC_EXISTS,
        "audit_exists": $AUDIT_EXISTS,
        "audit_rows": $AUDIT_ROWS
    },
    "files": {
        "recon_csv": $RECON_CSV_JSON,
        "summary_csv": $SUMMARY_CSV_JSON
    },
    "app_running": $APP_RUNNING,
    "task_start_time": $TASK_START
}
ENDJSON

echo "Export complete. Result:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
