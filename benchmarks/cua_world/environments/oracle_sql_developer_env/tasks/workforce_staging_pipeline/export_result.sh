#!/bin/bash
# Export results for Workforce Planning Staging Pipeline task
echo "=== Exporting Workforce Staging Pipeline results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Ensure safe integer extraction
sanitize_int() { local val="$1" default="$2"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "$default"; fi; }

# Initialize variables
TABLE_EXISTS=false
COL_COUNT=0
ROW_COUNT=0
QUART_MIN=0
QUART_MAX=0
TENURE_NEG_COUNT=99
PREV_JOBS_NEG_COUNT=99
NULL_NAMES_COUNT=99
INDEX_EXISTS=false
INDEX_COL_COUNT=0
VIEW_EXISTS=false
VIEW_ROWS=0
CSV_EXISTS=false
CSV_LINES=0
CSV_SIZE=0

# --- Check Table ---
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner='HR' AND table_name='WORKFORCE_STAGING';" "system" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    TABLE_EXISTS=true
    
    COL_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_columns WHERE owner='HR' AND table_name='WORKFORCE_STAGING';" "system" | tr -d '[:space:]')
    COL_COUNT=$(sanitize_int "$COL_COUNT" "0")
    
    ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM hr.workforce_staging;" "system" | tr -d '[:space:]')
    ROW_COUNT=$(sanitize_int "$ROW_COUNT" "0")
    
    if [ "$ROW_COUNT" -gt 0 ]; then
        QUART_MIN=$(oracle_query_raw "SELECT NVL(MIN(salary_quartile), 0) FROM hr.workforce_staging;" "system" | tr -d '[:space:]')
        QUART_MIN=$(sanitize_int "$QUART_MIN" "0")
        
        QUART_MAX=$(oracle_query_raw "SELECT NVL(MAX(salary_quartile), 0) FROM hr.workforce_staging;" "system" | tr -d '[:space:]')
        QUART_MAX=$(sanitize_int "$QUART_MAX" "0")
        
        TENURE_NEG_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM hr.workforce_staging WHERE tenure_years < 0;" "system" | tr -d '[:space:]')
        TENURE_NEG_COUNT=$(sanitize_int "$TENURE_NEG_COUNT" "99")
        
        PREV_JOBS_NEG_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM hr.workforce_staging WHERE previous_jobs_count < 0;" "system" | tr -d '[:space:]')
        PREV_JOBS_NEG_COUNT=$(sanitize_int "$PREV_JOBS_NEG_COUNT" "99")
        
        NULL_NAMES_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM hr.workforce_staging WHERE full_name IS NULL OR TRIM(full_name) = '';" "system" | tr -d '[:space:]')
        NULL_NAMES_COUNT=$(sanitize_int "$NULL_NAMES_COUNT" "99")
    fi
fi

# --- Check Index ---
IDX_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_indexes WHERE owner='HR' AND index_name='IDX_WS_DEPT_QUARTILE' AND table_name='WORKFORCE_STAGING';" "system" | tr -d '[:space:]')
if [ "${IDX_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    INDEX_EXISTS=true
    INDEX_COL_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_ind_columns WHERE index_owner='HR' AND index_name='IDX_WS_DEPT_QUARTILE' AND column_name IN ('DEPARTMENT_NAME','SALARY_QUARTILE');" "system" | tr -d '[:space:]')
    INDEX_COL_COUNT=$(sanitize_int "$INDEX_COL_COUNT" "0")
fi

# --- Check View ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='HR' AND view_name='WORKFORCE_SUMMARY_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VIEW_EXISTS=true
    VIEW_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM hr.workforce_summary_vw;" "system" | tr -d '[:space:]')
    VIEW_ROWS=$(sanitize_int "$VIEW_ROWS" "0")
fi

# --- Check CSV ---
CSV_PATH="/home/ga/Documents/exports/workforce_staging.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_LINES=$(grep -v '^$' "$CSV_PATH" | wc -l 2>/dev/null || echo "0")
fi

# --- Collect GUI evidence ---
GUI_EVIDENCE=$(collect_gui_evidence)

# --- Create JSON Report ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "table_exists": $TABLE_EXISTS,
    "col_count": $COL_COUNT,
    "row_count": $ROW_COUNT,
    "quart_min": $QUART_MIN,
    "quart_max": $QUART_MAX,
    "tenure_neg_count": $TENURE_NEG_COUNT,
    "prev_jobs_neg_count": $PREV_JOBS_NEG_COUNT,
    "null_names_count": $NULL_NAMES_COUNT,
    "index_exists": $INDEX_EXISTS,
    "index_col_count": $INDEX_COL_COUNT,
    "view_exists": $VIEW_EXISTS,
    "view_rows": $VIEW_ROWS,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_lines": $CSV_LINES,
    $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="