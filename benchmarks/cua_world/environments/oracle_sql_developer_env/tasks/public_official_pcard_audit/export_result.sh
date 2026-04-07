#!/bin/bash
echo "=== Exporting Public Official P-Card Audit results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

take_screenshot /tmp/task_end_screenshot.png

# Initialize flags and metrics
VW_SPLIT_EXISTS=false
SPLIT_FOUND_EMP=""
VW_WEEKEND_EXISTS=false
WEEKEND_FOUND_EMP=""
VW_CROSS_DUP_EXISTS=false
DUP_FOUND_PAIR=""
VW_PROHIBITED_EXISTS=false
PROHIBITED_FOUND_EMP=""
MV_SUMMARY_EXISTS=false
CSV_EXISTS=false
CSV_SIZE=0
AGENCY1_VIOLATORS=0
AGENCY2_VIOLATORS=0
AGENCY2_PROHIBITED_SPEND=0

# 1. Check VW_SPLIT_TXNS
CHECK_SPLIT=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'STATE_AUDIT' AND view_name = 'VW_SPLIT_TXNS';" "system" | tr -d '[:space:]')
if [ "${CHECK_SPLIT:-0}" -gt 0 ] 2>/dev/null; then
    VW_SPLIT_EXISTS=true
    SPLIT_FOUND_EMP=$(oracle_query_raw "SELECT emp_id FROM state_audit.VW_SPLIT_TXNS WHERE ROWNUM = 1;" "system" | tr -d '[:space:]')
fi

# 2. Check VW_WEEKEND_VIOLATIONS
CHECK_WEEKEND=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'STATE_AUDIT' AND view_name = 'VW_WEEKEND_VIOLATIONS';" "system" | tr -d '[:space:]')
if [ "${CHECK_WEEKEND:-0}" -gt 0 ] 2>/dev/null; then
    VW_WEEKEND_EXISTS=true
    WEEKEND_FOUND_EMP=$(oracle_query_raw "SELECT emp_id FROM state_audit.VW_WEEKEND_VIOLATIONS WHERE ROWNUM = 1;" "system" | tr -d '[:space:]')
fi

# 3. Check VW_CROSS_EMP_DUPLICATES
CHECK_DUP=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'STATE_AUDIT' AND view_name = 'VW_CROSS_EMP_DUPLICATES';" "system" | tr -d '[:space:]')
if [ "${CHECK_DUP:-0}" -gt 0 ] 2>/dev/null; then
    VW_CROSS_DUP_EXISTS=true
    DUP_FOUND_PAIR=$(oracle_query_raw "SELECT emp_id_1 || '-' || emp_id_2 FROM state_audit.VW_CROSS_EMP_DUPLICATES WHERE ROWNUM = 1;" "system" | tr -d '[:space:]')
fi

# 4. Check VW_PROHIBITED_SPEND
CHECK_PROHIBITED=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'STATE_AUDIT' AND view_name = 'VW_PROHIBITED_SPEND';" "system" | tr -d '[:space:]')
if [ "${CHECK_PROHIBITED:-0}" -gt 0 ] 2>/dev/null; then
    VW_PROHIBITED_EXISTS=true
    PROHIBITED_FOUND_EMP=$(oracle_query_raw "SELECT emp_id FROM state_audit.VW_PROHIBITED_SPEND WHERE ROWNUM = 1;" "system" | tr -d '[:space:]')
fi

# 5. Check MV_AGENCY_RISK_SUMMARY
CHECK_MV=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'STATE_AUDIT' AND mview_name = 'MV_AGENCY_RISK_SUMMARY';" "system" | tr -d '[:space:]')
if [ "${CHECK_MV:-0}" -gt 0 ] 2>/dev/null; then
    MV_SUMMARY_EXISTS=true
    
    # Query summary metrics to verify accuracy
    AGENCY1_VIOLATORS=$(oracle_query_raw "SELECT total_violating_employees FROM state_audit.MV_AGENCY_RISK_SUMMARY WHERE agency_name = 'Department of Transportation';" "system" | tr -d '[:space:]')
    AGENCY2_VIOLATORS=$(oracle_query_raw "SELECT total_violating_employees FROM state_audit.MV_AGENCY_RISK_SUMMARY WHERE agency_name = 'Department of Education';" "system" | tr -d '[:space:]')
    AGENCY2_PROHIBITED_SPEND=$(oracle_query_raw "SELECT total_prohibited_spend FROM state_audit.MV_AGENCY_RISK_SUMMARY WHERE agency_name = 'Department of Education';" "system" | tr -d '[:space:]')
fi

# 6. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/agency_audit_summary.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_EXISTS="true"
        CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    fi
fi

# Collect GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Export to JSON
TEMP_JSON=$(mktemp /tmp/pcard_audit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "vw_split_exists": $VW_SPLIT_EXISTS,
    "split_found_emp": "${SPLIT_FOUND_EMP:-}",
    "vw_weekend_exists": $VW_WEEKEND_EXISTS,
    "weekend_found_emp": "${WEEKEND_FOUND_EMP:-}",
    "vw_cross_dup_exists": $VW_CROSS_DUP_EXISTS,
    "dup_found_pair": "${DUP_FOUND_PAIR:-}",
    "vw_prohibited_exists": $VW_PROHIBITED_EXISTS,
    "prohibited_found_emp": "${PROHIBITED_FOUND_EMP:-}",
    "mv_summary_exists": $MV_SUMMARY_EXISTS,
    "agency1_violators": ${AGENCY1_VIOLATORS:-0},
    "agency2_violators": ${AGENCY2_VIOLATORS:-0},
    "agency2_prohibited_spend": ${AGENCY2_PROHIBITED_SPEND:-0},
    "csv_exists": ${CSV_EXISTS:-false},
    "csv_size": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

# Move securely
rm -f /tmp/pcard_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pcard_audit_result.json
chmod 666 /tmp/pcard_audit_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/pcard_audit_result.json"
cat /tmp/pcard_audit_result.json
echo "=== Export complete ==="