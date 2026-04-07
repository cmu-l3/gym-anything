#!/bin/bash
# Export results for Manufacturing SPC Quality Analysis task
echo "=== Exporting Manufacturing SPC Quality Analysis results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png ga

# Sanitize integer outputs
sanitize_int() { local val="$1" default="$2"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "$default"; fi; }

# Initialize variables
PROCESS_CAPABILITY_VW_EXISTS=false
PROCESS_CAPABILITY_ANALYTICS=false
CPK_COMPUTED=false
CONTROL_VIOLATIONS_EXISTS=false
DETECT_PROC_EXISTS=false
VIOLATIONS_POPULATED=0
MULTIPLE_RULES=0
DEFECT_PARETO_EXISTS=false
PARETO_WINDOW_USED=false
CALIBRATION_ALERTS_EXISTS=false
QUALITY_AUDIT_MV_EXISTS=false
AUDIT_ROLLUP_USED=false
CSV_EXISTS=false
CSV_SIZE=0
CSV_HAS_DATA=false

# 1. PROCESS_CAPABILITY_VW
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'QC_ENGINEER' AND view_name = 'PROCESS_CAPABILITY_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROCESS_CAPABILITY_VW_EXISTS=true
    
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'QC_ENGINEER' AND view_name = 'PROCESS_CAPABILITY_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "OVER\s*\(|STDDEV|AVG" 2>/dev/null; then
        PROCESS_CAPABILITY_ANALYTICS=true
    fi
    
    # Check if Cpk was successfully computed (returns numeric values)
    CPK_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM (SELECT 1 FROM qc_engineer.process_capability_vw WHERE cpk IS NOT NULL AND ROWNUM = 1);" "system" 2>/dev/null | tr -d '[:space:]')
    if [ "${CPK_CHECK:-0}" -gt 0 ] 2>/dev/null; then
        CPK_COMPUTED=true
    fi
fi

# 2. CONTROL_VIOLATIONS
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'QC_ENGINEER' AND table_name = 'CONTROL_VIOLATIONS';" "system" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CONTROL_VIOLATIONS_EXISTS=true
    
    VIOL_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM qc_engineer.control_violations;" "system" 2>/dev/null | tr -d '[:space:]')
    VIOLATIONS_POPULATED=$(sanitize_int "$VIOL_COUNT" "0")
    
    RULES_COUNT=$(oracle_query_raw "SELECT COUNT(DISTINCT rule_number) FROM qc_engineer.control_violations;" "system" 2>/dev/null | tr -d '[:space:]')
    MULTIPLE_RULES=$(sanitize_int "$RULES_COUNT" "0")
fi

PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'QC_ENGINEER' AND object_name = 'PROC_DETECT_VIOLATIONS';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    DETECT_PROC_EXISTS=true
fi

# 3. DEFECT_PARETO_VW
DP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'QC_ENGINEER' AND view_name = 'DEFECT_PARETO_VW';" "system" | tr -d '[:space:]')
if [ "${DP_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    DEFECT_PARETO_EXISTS=true
    
    DP_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'QC_ENGINEER' AND view_name = 'DEFECT_PARETO_VW';" "system" 2>/dev/null)
    if echo "$DP_TEXT" | grep -qiE "SUM.*OVER.*ORDER" 2>/dev/null; then
        PARETO_WINDOW_USED=true
    fi
fi

# 4. CALIBRATION_ALERTS_VW
CA_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'QC_ENGINEER' AND view_name = 'CALIBRATION_ALERTS_VW';" "system" | tr -d '[:space:]')
if [ "${CA_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CALIBRATION_ALERTS_EXISTS=true
fi

# 5. QUALITY_AUDIT_MV
QA_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'QC_ENGINEER' AND mview_name = 'QUALITY_AUDIT_MV';" "system" | tr -d '[:space:]')
if [ "${QA_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    QUALITY_AUDIT_MV_EXISTS=true
    
    QA_TEXT=$(oracle_query_raw "SELECT query FROM all_mviews WHERE owner = 'QC_ENGINEER' AND mview_name = 'QUALITY_AUDIT_MV';" "system" 2>/dev/null)
    if echo "$QA_TEXT" | grep -qiE "ROLLUP|CUBE" 2>/dev/null; then
        AUDIT_ROLLUP_USED=true
    fi
fi

# 6. CSV Export Check
CSV_PATH="/home/ga/quality_audit_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    if grep -qiE "line|part|defect|cpk" "$CSV_PATH" 2>/dev/null; then
        CSV_HAS_DATA=true
    fi
fi

# Collect GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create Output JSON
TEMP_JSON=$(mktemp /tmp/spc_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "process_capability_vw_exists": $PROCESS_CAPABILITY_VW_EXISTS,
    "process_capability_analytics": $PROCESS_CAPABILITY_ANALYTICS,
    "cpk_computed": $CPK_COMPUTED,
    "control_violations_exists": $CONTROL_VIOLATIONS_EXISTS,
    "detect_proc_exists": $DETECT_PROC_EXISTS,
    "violations_populated": $VIOLATIONS_POPULATED,
    "multiple_rules_detected": $MULTIPLE_RULES,
    "defect_pareto_exists": $DEFECT_PARETO_EXISTS,
    "pareto_window_used": $PARETO_WINDOW_USED,
    "calibration_alerts_exists": $CALIBRATION_ALERTS_EXISTS,
    "quality_audit_mv_exists": $QUALITY_AUDIT_MV_EXISTS,
    "audit_rollup_used": $AUDIT_ROLLUP_USED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_has_data": $CSV_HAS_DATA,
    $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/spc_task_result.json 2>/dev/null || sudo rm -f /tmp/spc_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/spc_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/spc_task_result.json
chmod 666 /tmp/spc_task_result.json 2>/dev/null || sudo chmod 666 /tmp/spc_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/spc_task_result.json"
cat /tmp/spc_task_result.json