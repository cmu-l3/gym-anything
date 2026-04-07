#!/bin/bash
echo "=== Exporting SAM License Audit results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/task_final.png ga

# 1. Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Initialize flags
NORM_VW_EXISTS="false"
NORM_REGEX_CORRECT="false"
LIC_VW_EXISTS="false"
LIC_MATH_CORRECT="false"
ELP_MV_EXISTS="false"
ELP_MATH_CORRECT="false"
PROC_EXISTS="false"
LOG_TABLE_EXISTS="false"
LOG_POPULATED="false"
CSV_EXISTS="false"
CSV_MODIFIED_DURING_TASK="false"
CSV_SIZE="0"

# 2. Check NORMALIZED_INSTALLS_VW
NORM_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'SAM_ADMIN' AND view_name = 'NORMALIZED_INSTALLS_VW';" "system" | tr -d '[:space:]')
if [ "${NORM_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    NORM_VW_EXISTS="true"
    # Check if regex properly extracted '2019' and 'Enterprise' for H-001
    H1_NORM=$(oracle_query_raw "SELECT COUNT(*) FROM sam_admin.normalized_installs_vw WHERE host_id = 'H-001' AND version = '2019' AND edition LIKE 'Enterprise%';" "system" | tr -d '[:space:]')
    if [ "${H1_NORM:-0}" -gt 0 ] 2>/dev/null; then
        NORM_REGEX_CORRECT="true"
    fi
fi

# 3. Check LICENSES_REQUIRED_VW
LIC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'SAM_ADMIN' AND view_name = 'LICENSES_REQUIRED_VW';" "system" | tr -d '[:space:]')
if [ "${LIC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    LIC_VW_EXISTS="true"
    # Check specific business rule math
    # H-001: 2 cores -> SQL Server -> Min 4 -> Expected: 4
    # H-002: DEV -> Expected: 0
    # H-003: 8 cores -> Win Server -> Min 16 -> Expected: 16
    # H-004: 11 cores -> Oracle 0.5 factor -> ceil(5.5) -> Expected: 6
    MATH_CORRECT_COUNT=0
    H1_LIC=$(oracle_query_raw "SELECT required_licenses FROM sam_admin.licenses_required_vw WHERE host_id = 'H-001';" "system" | tr -d '[:space:]')
    if [ "${H1_LIC:-99}" = "4" ] 2>/dev/null; then MATH_CORRECT_COUNT=$((MATH_CORRECT_COUNT + 1)); fi
    
    H2_LIC=$(oracle_query_raw "SELECT required_licenses FROM sam_admin.licenses_required_vw WHERE host_id = 'H-002';" "system" | tr -d '[:space:]')
    if [ "${H2_LIC:-99}" = "0" ] 2>/dev/null; then MATH_CORRECT_COUNT=$((MATH_CORRECT_COUNT + 1)); fi
    
    H3_LIC=$(oracle_query_raw "SELECT required_licenses FROM sam_admin.licenses_required_vw WHERE host_id = 'H-003';" "system" | tr -d '[:space:]')
    if [ "${H3_LIC:-99}" = "16" ] 2>/dev/null; then MATH_CORRECT_COUNT=$((MATH_CORRECT_COUNT + 1)); fi
    
    H4_LIC=$(oracle_query_raw "SELECT required_licenses FROM sam_admin.licenses_required_vw WHERE host_id = 'H-004';" "system" | tr -d '[:space:]')
    if [ "${H4_LIC:-99}" = "6" ] 2>/dev/null; then MATH_CORRECT_COUNT=$((MATH_CORRECT_COUNT + 1)); fi
    
    if [ "$MATH_CORRECT_COUNT" -eq 4 ]; then
        LIC_MATH_CORRECT="true"
    fi
fi

# 4. Check EFFECTIVE_LICENSE_POSITION_MV
ELP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'SAM_ADMIN' AND mview_name = 'EFFECTIVE_LICENSE_POSITION_MV';" "system" | tr -d '[:space:]')
if [ "${ELP_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ELP_MV_EXISTS="true"
    # H-001 & H-007 (DEV=0) -> Total SQL 2019 Ent = 4. Entitlements = 2. Variance = -2. Exposure = 2 * 3500 = 7000
    # Expected sum of financial_exposure across all products = 7000 (SQL) + 30000 (Oracle 12c) + 14400 (Win 2022) = 51400.
    # Wait, H-003 = 16. H-008 = 16 (since min 16, and it has 16). Total Windows Server = 32. Entitlements = 10. Variance = -22. Exposure = 22 * 1200 = 26400.
    # Actually, we just check if it correctly calculates negative variance and multiplies by price.
    SQL_EXPOSURE=$(oracle_query_raw "SELECT financial_exposure FROM sam_admin.effective_license_position_mv WHERE product_name = 'Microsoft SQL Server' AND version = '2019' AND edition LIKE 'Enterprise%';" "system" | tr -d '[:space:]')
    if [ "${SQL_EXPOSURE:-0}" = "7000" ] 2>/dev/null; then
        ELP_MATH_CORRECT="true"
    fi
fi

# 5. Check Procedure and Log
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'SAM_ADMIN' AND object_name = 'PROC_FLAG_SHORTFALL_HOSTS';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS="true"
fi

LOG_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'SAM_ADMIN' AND table_name = 'AUDIT_ACTION_LOG';" "system" | tr -d '[:space:]')
if [ "${LOG_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    LOG_TABLE_EXISTS="true"
    LOG_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM sam_admin.audit_action_log;" "system" | tr -d '[:space:]')
    if [ "${LOG_ROWS:-0}" -gt 0 ] 2>/dev/null; then
        LOG_POPULATED="true"
    fi
fi

# 6. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/elp_audit_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED_DURING_TASK="true"
    fi
fi

# 7. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "norm_vw_exists": $NORM_VW_EXISTS,
    "norm_regex_correct": $NORM_REGEX_CORRECT,
    "lic_vw_exists": $LIC_VW_EXISTS,
    "lic_math_correct": $LIC_MATH_CORRECT,
    "elp_mv_exists": $ELP_MV_EXISTS,
    "elp_math_correct": $ELP_MATH_CORRECT,
    "proc_exists": $PROC_EXISTS,
    "log_table_exists": $LOG_TABLE_EXISTS,
    "log_populated": $LOG_POPULATED,
    "csv_exists": $CSV_EXISTS,
    "csv_modified_during_task": $CSV_MODIFIED_DURING_TASK,
    "csv_size": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

# Move to final location
rm -f /tmp/sam_audit_result.json 2>/dev/null || sudo rm -f /tmp/sam_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/sam_audit_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/sam_audit_result.json
chmod 666 /tmp/sam_audit_result.json 2>/dev/null || sudo chmod 666 /tmp/sam_audit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/sam_audit_result.json"
cat /tmp/sam_audit_result.json
echo "=== Export complete ==="