#!/bin/bash
echo "=== Exporting Medicare Opioid task results ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_final.png ga

# Check FACT table
FACT_EXISTS=false
FACT_ROWS=0
FACT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'MEDICARE_ADMIN' AND table_name = 'PRESCRIPTION_FACT';" "system" | tr -d '[:space:]')
if [ "${FACT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FACT_EXISTS=true
    FACT_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM medicare_admin.prescription_fact;" "system" | tr -d '[:space:]')
fi

# Check MME view
MME_VW_EXISTS=false
MME_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'MEDICARE_ADMIN' AND view_name = 'PRESCRIPTION_MME_VW';" "system" | tr -d '[:space:]')
if [ "${MME_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MME_VW_EXISTS=true
fi

# Check STATS MV
STATS_MV_EXISTS=false
WINDOW_FUNC_USED=false
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'MEDICARE_ADMIN' AND mview_name = 'PRESCRIBER_STATS_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    STATS_MV_EXISTS=true
    # Check for window functions
    MV_TEXT=$(oracle_query_raw "SELECT query FROM all_mviews WHERE owner = 'MEDICARE_ADMIN' AND mview_name = 'PRESCRIBER_STATS_MV';" "system" 2>/dev/null)
    if echo "$MV_TEXT" | grep -qiE "OVER\s*\("; then
        WINDOW_FUNC_USED=true
    fi
fi

# Check TRENDS VW
TRENDS_VW_EXISTS=false
TR_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'MEDICARE_ADMIN' AND view_name = 'PRESCRIBER_TRENDS_VW';" "system" | tr -d '[:space:]')
if [ "${TR_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    TRENDS_VW_EXISTS=true
fi

# Check FLAGGED_AUDITS table
AUDITS_TBL_EXISTS=false
STAT_OUTLIER_COUNT=0
RAPID_ACCEL_COUNT=0
CRITICAL_RISK_COUNT=0
AT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'MEDICARE_ADMIN' AND table_name = 'FLAGGED_AUDITS';" "system" | tr -d '[:space:]')
if [ "${AT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    AUDITS_TBL_EXISTS=true
    STAT_OUTLIER_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM medicare_admin.flagged_audits WHERE flag_reason = 'STATISTICAL_OUTLIER';" "system" | tr -d '[:space:]')
    RAPID_ACCEL_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM medicare_admin.flagged_audits WHERE flag_reason = 'RAPID_ACCELERATION';" "system" | tr -d '[:space:]')
    CRITICAL_RISK_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM medicare_admin.flagged_audits WHERE flag_reason = 'CRITICAL_RISK';" "system" | tr -d '[:space:]')
fi

# Check CSV
CSV_EXISTS=false
CSV_SIZE=0
if [ -f "/home/ga/Documents/exports/opioid_audit_targets.csv" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "/home/ga/Documents/exports/opioid_audit_targets.csv" 2>/dev/null || echo "0")
fi

# Check GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "fact_table_exists": $FACT_EXISTS,
    "fact_table_rows": ${FACT_ROWS:-0},
    "mme_vw_exists": $MME_VW_EXISTS,
    "stats_mv_exists": $STATS_MV_EXISTS,
    "window_func_used": $WINDOW_FUNC_USED,
    "trends_vw_exists": $TRENDS_VW_EXISTS,
    "audits_tbl_exists": $AUDITS_TBL_EXISTS,
    "stat_outlier_count": ${STAT_OUTLIER_COUNT:-0},
    "rapid_accel_count": ${RAPID_ACCEL_COUNT:-0},
    "critical_risk_count": ${CRITICAL_RISK_COUNT:-0},
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="