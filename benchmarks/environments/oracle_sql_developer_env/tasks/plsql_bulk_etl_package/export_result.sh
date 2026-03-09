#!/bin/bash
set -e

echo "=== Exporting PL/SQL Bulk ETL Package result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/plsql_bulk_etl_package_end.png

TASK_START=$(cat /tmp/plsql_bulk_etl_start_ts 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/exports/review_summary.csv"

PKG_SPEC_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'HR' AND object_name = 'REVIEW_ETL_PKG' AND object_type = 'PACKAGE';" "system" | tr -d '[:space:]')
PKG_BODY_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'HR' AND object_name = 'REVIEW_ETL_PKG' AND object_type = 'PACKAGE BODY';" "system" | tr -d '[:space:]')
BULK_COLLECT_FOUND=$(oracle_query_raw "SELECT COUNT(*) FROM all_source WHERE owner = 'HR' AND name = 'REVIEW_ETL_PKG' AND type = 'PACKAGE BODY' AND UPPER(text) LIKE '%BULK COLLECT%';" "system" | tr -d '[:space:]')
AUTONOMOUS_FOUND=$(oracle_query_raw "SELECT COUNT(*) FROM all_source WHERE owner = 'HR' AND name = 'REVIEW_ETL_PKG' AND type = 'PACKAGE BODY' AND UPPER(text) LIKE '%PRAGMA AUTONOMOUS_TRANSACTION%';" "system" | tr -d '[:space:]')
REF_CURSOR_FOUND=$(oracle_query_raw "SELECT COUNT(*) FROM all_source WHERE owner = 'HR' AND name = 'REVIEW_ETL_PKG' AND UPPER(text) LIKE '%REF CURSOR%';" "system" | tr -d '[:space:]')
PROCESS_PROC_FOUND=$(oracle_query_raw "SELECT COUNT(*) FROM all_source WHERE owner = 'HR' AND name = 'REVIEW_ETL_PKG' AND UPPER(text) LIKE '%PROCESS_REVIEWS%';" "system" | tr -d '[:space:]')
GET_UNPROCESSED_FOUND=$(oracle_query_raw "SELECT COUNT(*) FROM all_source WHERE owner = 'HR' AND name = 'REVIEW_ETL_PKG' AND UPPER(text) LIKE '%GET_UNPROCESSED%';" "system" | tr -d '[:space:]')

TOTAL_REVIEWS=$(oracle_query_raw "SELECT COUNT(*) FROM hr.perf_reviews;" "hr" | tr -d '[:space:]')
PROCESSED_REVIEWS=$(oracle_query_raw "SELECT COUNT(*) FROM hr.perf_reviews WHERE status = 'PROCESSED';" "hr" | tr -d '[:space:]')
NEW_REVIEWS=$(oracle_query_raw "SELECT COUNT(*) FROM hr.perf_reviews WHERE status = 'NEW';" "hr" | tr -d '[:space:]')
LOG_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM hr.etl_run_log;" "hr" | tr -d '[:space:]')
VIEW_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'HR' AND view_name = 'VW_REVIEW_SUMMARY';" "system" | tr -d '[:space:]')
VIEW_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM hr.vw_review_summary;" "hr" 2>/dev/null | tr -d '[:space:]' || echo "0")

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_LINE_COUNT=0
if [ -f "$OUTPUT_FILE" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW=true
    fi
    CSV_LINE_COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

cat > /tmp/plsql_bulk_etl_package_result.json <<EOF
{
  "package_spec_exists": $([ "${PKG_SPEC_EXISTS:-0}" -gt 0 ] && echo true || echo false),
  "package_body_exists": $([ "${PKG_BODY_EXISTS:-0}" -gt 0 ] && echo true || echo false),
  "bulk_collect_found": $([ "${BULK_COLLECT_FOUND:-0}" -gt 0 ] && echo true || echo false),
  "autonomous_transaction_found": $([ "${AUTONOMOUS_FOUND:-0}" -gt 0 ] && echo true || echo false),
  "ref_cursor_found": $([ "${REF_CURSOR_FOUND:-0}" -gt 0 ] && echo true || echo false),
  "process_reviews_found": $([ "${PROCESS_PROC_FOUND:-0}" -gt 0 ] && echo true || echo false),
  "get_unprocessed_found": $([ "${GET_UNPROCESSED_FOUND:-0}" -gt 0 ] && echo true || echo false),
  "total_reviews": ${TOTAL_REVIEWS:-0},
  "processed_reviews": ${PROCESSED_REVIEWS:-0},
  "new_reviews": ${NEW_REVIEWS:-0},
  "log_rows": ${LOG_ROWS:-0},
  "view_exists": $([ "${VIEW_EXISTS:-0}" -gt 0 ] && echo true || echo false),
  "view_rows": ${VIEW_ROWS:-0},
  "csv_exists": ${CSV_EXISTS},
  "csv_is_new": ${CSV_IS_NEW},
  "csv_line_count": ${CSV_LINE_COUNT:-0},
  ${GUI_EVIDENCE},
  "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/plsql_bulk_etl_package_result.json
cat /tmp/plsql_bulk_etl_package_result.json
echo "=== Export complete ==="
