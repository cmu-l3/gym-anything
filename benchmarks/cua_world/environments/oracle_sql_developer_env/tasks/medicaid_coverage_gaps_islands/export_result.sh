#!/bin/bash
echo "=== Exporting Medicaid Coverage Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Initialize all flags
CONTINUOUS_VW_EXISTS=false
CONTINUOUS_ROWS=0
GAPS_VW_EXISTS=false
GAPS_ROWS=0
HEDIS_TBL_EXISTS=false
HEDIS_TOTAL_ROWS=0
HEDIS_MEETS_Y=0
HEDIS_MEETS_N=0
PROC_EXISTS=false
PROC_VALID=false
CSV_EXISTS=false
CSV_SIZE=0
CSV_NEWER=false

# 1. Check CONTINUOUS_COVERAGE_VW
CV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'MEDICAID_ANALYST' AND view_name = 'CONTINUOUS_COVERAGE_VW';" "system" | tr -d '[:space:]')
if [ "${CV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CONTINUOUS_VW_EXISTS=true
    CONTINUOUS_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM medicaid_analyst.continuous_coverage_vw;" "system" | tr -d '[:space:]')
    CONTINUOUS_ROWS=${CONTINUOUS_ROWS:-0}
fi

# 2. Check COVERAGE_GAPS_VW
CG_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'MEDICAID_ANALYST' AND view_name = 'COVERAGE_GAPS_VW';" "system" | tr -d '[:space:]')
if [ "${CG_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    GAPS_VW_EXISTS=true
    GAPS_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM medicaid_analyst.coverage_gaps_vw;" "system" | tr -d '[:space:]')
    GAPS_ROWS=${GAPS_ROWS:-0}
fi

# 3. Check HEDIS_METRICS_2023 Table
HM_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'MEDICAID_ANALYST' AND table_name = 'HEDIS_METRICS_2023';" "system" | tr -d '[:space:]')
if [ "${HM_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    HEDIS_TBL_EXISTS=true
    HEDIS_TOTAL_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM medicaid_analyst.hedis_metrics_2023;" "system" | tr -d '[:space:]')
    HEDIS_TOTAL_ROWS=${HEDIS_TOTAL_ROWS:-0}
    
    HEDIS_MEETS_Y=$(oracle_query_raw "SELECT COUNT(*) FROM medicaid_analyst.hedis_metrics_2023 WHERE UPPER(meets_hedis_criteria) = 'Y';" "system" | tr -d '[:space:]')
    HEDIS_MEETS_Y=${HEDIS_MEETS_Y:-0}
    
    HEDIS_MEETS_N=$(oracle_query_raw "SELECT COUNT(*) FROM medicaid_analyst.hedis_metrics_2023 WHERE UPPER(meets_hedis_criteria) = 'N';" "system" | tr -d '[:space:]')
    HEDIS_MEETS_N=${HEDIS_MEETS_N:-0}
fi

# 4. Check PROC_REFRESH_METRICS Stored Procedure
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'MEDICAID_ANALYST' AND object_name = 'PROC_REFRESH_METRICS' AND object_type = 'PROCEDURE';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS=true
    PROC_VAL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'MEDICAID_ANALYST' AND object_name = 'PROC_REFRESH_METRICS' AND object_type = 'PROCEDURE' AND status = 'VALID';" "system" | tr -d '[:space:]')
    if [ "${PROC_VAL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
        PROC_VALID=true
    fi
fi

# 5. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/hedis_2023_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -ge "$TASK_START" ]; then
        CSV_NEWER=true
    fi
fi

# 6. Check GUI Usage Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# 7. Compile JSON results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "continuous_vw_exists": $CONTINUOUS_VW_EXISTS,
    "continuous_rows": $CONTINUOUS_ROWS,
    "gaps_vw_exists": $GAPS_VW_EXISTS,
    "gaps_rows": $GAPS_ROWS,
    "hedis_tbl_exists": $HEDIS_TBL_EXISTS,
    "hedis_total_rows": $HEDIS_TOTAL_ROWS,
    "hedis_meets_y": $HEDIS_MEETS_Y,
    "hedis_meets_n": $HEDIS_MEETS_N,
    "proc_exists": $PROC_EXISTS,
    "proc_valid": $PROC_VALID,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_newer": $CSV_NEWER,
    ${GUI_EVIDENCE}
}
EOF

# Move to final location
rm -f /tmp/medicaid_result.json 2>/dev/null || sudo rm -f /tmp/medicaid_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/medicaid_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/medicaid_result.json
chmod 666 /tmp/medicaid_result.json 2>/dev/null || sudo chmod 666 /tmp/medicaid_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results written to /tmp/medicaid_result.json"
cat /tmp/medicaid_result.json
echo "=== Export Complete ==="