#!/bin/bash
# Export results for Retail Fair Workweek Compliance Audit task
echo "=== Exporting Compliance Audit results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize flags
CLOPENING_VW_EXISTS=false
PREDICTIVE_VW_EXISTS=false
MEAL_BREAK_VW_EXISTS=false
PENALTY_MV_EXISTS=false
AGENT_TOTAL=0
LAG_USED=false
NVL_COALESCE_USED=false
CSV_EXISTS=false
CSV_SIZE=0

# --- Check Views ---
C_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='HR_COMPLIANCE' AND view_name='CLOPENING_VIOLATIONS_VW';" "system" | tr -d '[:space:]')
if [ "${C_CHECK:-0}" -gt 0 ] 2>/dev/null; then CLOPENING_VW_EXISTS=true; fi

P_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='HR_COMPLIANCE' AND view_name='PREDICTIVE_SCHEDULING_VW';" "system" | tr -d '[:space:]')
if [ "${P_CHECK:-0}" -gt 0 ] 2>/dev/null; then PREDICTIVE_VW_EXISTS=true; fi

M_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='HR_COMPLIANCE' AND view_name='MEAL_BREAK_VIOLATIONS_VW';" "system" | tr -d '[:space:]')
if [ "${M_CHECK:-0}" -gt 0 ] 2>/dev/null; then MEAL_BREAK_VW_EXISTS=true; fi

MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner='HR_COMPLIANCE' AND mview_name='PAYROLL_PENALTY_SUMMARY_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then PENALTY_MV_EXISTS=true; fi

# --- Check for Keywords in Source ---
VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='HR_COMPLIANCE';" "system" 2>/dev/null)
if echo "$VW_TEXT" | grep -qiE "LAG\s*\(" 2>/dev/null; then LAG_USED=true; fi
if echo "$VW_TEXT" | grep -qiE "NVL|COALESCE" 2>/dev/null; then NVL_COALESCE_USED=true; fi

# --- Calculate Math Accuracy ---
# Query the agent's materialized view for the grand total. If perfect, it should be 111 (50 + 25 + 18 + 18).
if [ "$PENALTY_MV_EXISTS" = "true" ]; then
    AGENT_TOTAL_RAW=$(oracle_query_raw "SELECT SUM(grand_total_penalty) FROM hr_compliance.payroll_penalty_summary_mv;" "system" | tr -d '[:space:]')
    # Filter out anything non-numeric just in case
    if [[ "$AGENT_TOTAL_RAW" =~ ^[0-9.]+$ ]]; then
        AGENT_TOTAL=$AGENT_TOTAL_RAW
    fi
fi

# --- Check CSV ---
CSV_PATH="/home/ga/Documents/exports/fair_workweek_penalties.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# --- Collect GUI Evidence ---
GUI_EVIDENCE=$(collect_gui_evidence)

# --- Create JSON payload ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "clopening_vw_exists": $CLOPENING_VW_EXISTS,
    "predictive_vw_exists": $PREDICTIVE_VW_EXISTS,
    "meal_break_vw_exists": $MEAL_BREAK_VW_EXISTS,
    "penalty_mv_exists": $PENALTY_MV_EXISTS,
    "agent_total": $AGENT_TOTAL,
    "lag_used": $LAG_USED,
    "nvl_coalesce_used": $NVL_COALESCE_USED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

# Move payload
rm -f /tmp/compliance_audit_result.json 2>/dev/null || sudo rm -f /tmp/compliance_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/compliance_audit_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/compliance_audit_result.json
chmod 666 /tmp/compliance_audit_result.json 2>/dev/null || sudo chmod 666 /tmp/compliance_audit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON exported to /tmp/compliance_audit_result.json"
cat /tmp/compliance_audit_result.json
echo "=== Export Complete ==="