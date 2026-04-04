#!/bin/bash
# Export results for Analytics Data Warehouse Build task
echo "=== Exporting Analytics Warehouse results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize
FACT_TABLE_EXISTS=false
FACT_TABLE_NAME=""
FACT_ROW_COUNT=0
DIM_DEPARTMENT_EXISTS=false
DIM_JOB_EXISTS=false
DIM_COUNT=0
RPT_VIEW_EXISTS=false
RPT_VIEW_ROWS=0
ANALYTICS_TABLE_COUNT=0

# --- Count all FACT_* and DIM_* tables in ANALYTICS schema ---
ANALYTICS_TABLE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'ANALYTICS' AND table_name NOT LIKE 'STG%';" "system" | tr -d '[:space:]')
ANALYTICS_TABLE_COUNT=${ANALYTICS_TABLE_COUNT:-0}

# --- Check for FACT table (flexible: any table starting with FACT_) ---
FACT_TABLE_NAME=$(oracle_query_raw "SELECT table_name FROM all_tables WHERE owner = 'ANALYTICS' AND table_name LIKE 'FACT%' AND ROWNUM = 1;" "system" | tr -d '[:space:]')
if [ -n "$FACT_TABLE_NAME" ]; then
    FACT_TABLE_EXISTS=true
    FACT_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM analytics.${FACT_TABLE_NAME};" "system" | tr -d '[:space:]')
    FACT_ROW_COUNT=${FACT_ROW_COUNT:-0}
fi

# --- Check dimension tables ---
DIM_TABLE_LIST=$(oracle_query_raw "SELECT table_name FROM all_tables WHERE owner = 'ANALYTICS' AND table_name LIKE 'DIM%' ORDER BY table_name;" "system")
DIM_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'ANALYTICS' AND table_name LIKE 'DIM%';" "system" | tr -d '[:space:]')
DIM_COUNT=${DIM_COUNT:-0}

DIM_DEPT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'ANALYTICS' AND table_name = 'DIM_DEPARTMENT';" "system" | tr -d '[:space:]')
if [ "${DIM_DEPT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    DIM_DEPARTMENT_EXISTS=true
fi

DIM_JOB_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'ANALYTICS' AND table_name = 'DIM_JOB';" "system" | tr -d '[:space:]')
if [ "${DIM_JOB_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    DIM_JOB_EXISTS=true
fi

# --- Check RPT_DEPT_SALARY_SUMMARY view ---
VIEW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ANALYTICS' AND view_name = 'RPT_DEPT_SALARY_SUMMARY';" "system" | tr -d '[:space:]')
if [ "${VIEW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    RPT_VIEW_EXISTS=true
    RPT_VIEW_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM analytics.rpt_dept_salary_summary;" "system" | tr -d '[:space:]')
    RPT_VIEW_ROWS=${RPT_VIEW_ROWS:-0}
fi

# Get baseline counts
INITIAL_FACT_COUNT=$(cat /tmp/initial_fact_table_count 2>/dev/null || echo "0")
INITIAL_DIM_COUNT=$(cat /tmp/initial_dim_table_count 2>/dev/null || echo "0")

# Escape fact table name for JSON
FACT_TABLE_NAME_SAFE=$(echo "$FACT_TABLE_NAME" | tr -d '"\\')

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Write result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "fact_table_exists": $FACT_TABLE_EXISTS,
    "fact_table_name": "$FACT_TABLE_NAME_SAFE",
    "fact_row_count": ${FACT_ROW_COUNT:-0},
    "dim_department_exists": $DIM_DEPARTMENT_EXISTS,
    "dim_job_exists": $DIM_JOB_EXISTS,
    "dim_count": ${DIM_COUNT:-0},
    "rpt_view_exists": $RPT_VIEW_EXISTS,
    "rpt_view_rows": ${RPT_VIEW_ROWS:-0},
    "analytics_non_stg_table_count": ${ANALYTICS_TABLE_COUNT:-0},
    "initial_fact_count": ${INITIAL_FACT_COUNT:-0},
    "initial_dim_count": ${INITIAL_DIM_COUNT:-0},
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/analytics_warehouse_result.json 2>/dev/null || sudo rm -f /tmp/analytics_warehouse_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/analytics_warehouse_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/analytics_warehouse_result.json
chmod 666 /tmp/analytics_warehouse_result.json 2>/dev/null || sudo chmod 666 /tmp/analytics_warehouse_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/analytics_warehouse_result.json"
cat /tmp/analytics_warehouse_result.json
echo "=== Export complete ==="
