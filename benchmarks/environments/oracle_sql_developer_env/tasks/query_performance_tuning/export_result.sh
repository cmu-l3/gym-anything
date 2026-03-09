#!/bin/bash
# Export results for Query Performance Tuning task
echo "=== Exporting Query Performance Tuning results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize
TOTAL_INDEXES_ON_PERF=0
IDX_ORDER_AMOUNT=false
IDX_ORDER_DATE=false
IDX_CUSTOMER_ID=false
IDX_SALESPERSON_ID=false
IDX_CUSTOMER_DEPT=false
TUNING_REPORT_EXISTS=false
TUNING_REPORT_SIZE=0
REPORT_MENTIONS_EXPLAIN=false
REPORT_MENTIONS_INDEX=false
REPORT_MENTIONS_FULLSCAN=false

# --- Count all indexes on PERFORMANCE_ORDERS ---
TOTAL_INDEXES_ON_PERF=$(oracle_query_raw "SELECT COUNT(*) FROM all_indexes WHERE owner = 'HR' AND table_name = 'PERFORMANCE_ORDERS';" "system" | tr -d '[:space:]')
TOTAL_INDEXES_ON_PERF=${TOTAL_INDEXES_ON_PERF:-0}

# --- Check for indexes on specific columns (flexible name matching) ---
# An index on ORDER_AMOUNT column
OA_IDX=$(oracle_query_raw "SELECT COUNT(*) FROM all_ind_columns aic JOIN all_indexes ai ON aic.index_name = ai.index_name AND aic.index_owner = ai.owner WHERE ai.owner = 'HR' AND ai.table_name = 'PERFORMANCE_ORDERS' AND aic.column_name = 'ORDER_AMOUNT';" "system" | tr -d '[:space:]')
if [ "${OA_IDX:-0}" -gt 0 ] 2>/dev/null; then IDX_ORDER_AMOUNT=true; fi

# An index on ORDER_DATE column
OD_IDX=$(oracle_query_raw "SELECT COUNT(*) FROM all_ind_columns aic JOIN all_indexes ai ON aic.index_name = ai.index_name AND aic.index_owner = ai.owner WHERE ai.owner = 'HR' AND ai.table_name = 'PERFORMANCE_ORDERS' AND aic.column_name = 'ORDER_DATE';" "system" | tr -d '[:space:]')
if [ "${OD_IDX:-0}" -gt 0 ] 2>/dev/null; then IDX_ORDER_DATE=true; fi

# An index on CUSTOMER_ID column
CI_IDX=$(oracle_query_raw "SELECT COUNT(*) FROM all_ind_columns aic JOIN all_indexes ai ON aic.index_name = ai.index_name AND aic.index_owner = ai.owner WHERE ai.owner = 'HR' AND ai.table_name = 'PERFORMANCE_ORDERS' AND aic.column_name = 'CUSTOMER_ID';" "system" | tr -d '[:space:]')
if [ "${CI_IDX:-0}" -gt 0 ] 2>/dev/null; then IDX_CUSTOMER_ID=true; fi

# An index on SALESPERSON_ID column (bonus)
SP_IDX=$(oracle_query_raw "SELECT COUNT(*) FROM all_ind_columns aic JOIN all_indexes ai ON aic.index_name = ai.index_name AND aic.index_owner = ai.owner WHERE ai.owner = 'HR' AND ai.table_name = 'PERFORMANCE_ORDERS' AND aic.column_name = 'SALESPERSON_ID';" "system" | tr -d '[:space:]')
if [ "${SP_IDX:-0}" -gt 0 ] 2>/dev/null; then IDX_SALESPERSON_ID=true; fi

# An index on CUSTOMER_DEPT_ID (bonus)
CD_IDX=$(oracle_query_raw "SELECT COUNT(*) FROM all_ind_columns aic JOIN all_indexes ai ON aic.index_name = ai.index_name AND aic.index_owner = ai.owner WHERE ai.owner = 'HR' AND ai.table_name = 'PERFORMANCE_ORDERS' AND aic.column_name = 'CUSTOMER_DEPT_ID';" "system" | tr -d '[:space:]')
if [ "${CD_IDX:-0}" -gt 0 ] 2>/dev/null; then IDX_CUSTOMER_DEPT=true; fi

# --- Check tuning report file ---
REPORT_PATH="/home/ga/Documents/exports/tuning_report.txt"
if [ -f "$REPORT_PATH" ]; then
    TUNING_REPORT_EXISTS=true
    TUNING_REPORT_SIZE=$(wc -c < "$REPORT_PATH" 2>/dev/null)
    TUNING_REPORT_SIZE=${TUNING_REPORT_SIZE:-0}

    # Check for explain plan / execution plan keywords
    if grep -qiE "explain|execution plan|execution_plan|TABLE ACCESS FULL|full.scan|full table" "$REPORT_PATH" 2>/dev/null; then
        REPORT_MENTIONS_EXPLAIN=true
    fi

    # Check for index-related keywords
    if grep -qiE "index|INDEX RANGE SCAN|create index|idx_" "$REPORT_PATH" 2>/dev/null; then
        REPORT_MENTIONS_INDEX=true
    fi

    # Check for full scan identification
    if grep -qiE "full scan|TABLE ACCESS|access full|missing index|no index" "$REPORT_PATH" 2>/dev/null; then
        REPORT_MENTIONS_FULLSCAN=true
    fi
fi

# Get baseline
INITIAL_INDEX_COUNT=$(cat /tmp/initial_perf_order_index_count 2>/dev/null || echo "0")

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Write result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "total_indexes_on_performance_orders": ${TOTAL_INDEXES_ON_PERF:-0},
    "idx_order_amount": $IDX_ORDER_AMOUNT,
    "idx_order_date": $IDX_ORDER_DATE,
    "idx_customer_id": $IDX_CUSTOMER_ID,
    "idx_salesperson_id": $IDX_SALESPERSON_ID,
    "idx_customer_dept": $IDX_CUSTOMER_DEPT,
    "tuning_report_exists": $TUNING_REPORT_EXISTS,
    "tuning_report_size": ${TUNING_REPORT_SIZE:-0},
    "report_mentions_explain": $REPORT_MENTIONS_EXPLAIN,
    "report_mentions_index": $REPORT_MENTIONS_INDEX,
    "report_mentions_fullscan": $REPORT_MENTIONS_FULLSCAN,
    "initial_index_count": ${INITIAL_INDEX_COUNT:-0},
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/query_perf_tuning_result.json 2>/dev/null || sudo rm -f /tmp/query_perf_tuning_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/query_perf_tuning_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/query_perf_tuning_result.json
chmod 666 /tmp/query_perf_tuning_result.json 2>/dev/null || sudo chmod 666 /tmp/query_perf_tuning_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/query_perf_tuning_result.json"
cat /tmp/query_perf_tuning_result.json
echo "=== Export complete ==="
