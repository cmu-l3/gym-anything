#!/bin/bash
# Export results for Court Data Quality Audit task
echo "=== Exporting Court Audit results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png ga

# Collect GUI Evidence
GUI_JSON=$(collect_gui_evidence)

# Helper function to get clean numeric results
get_numeric() {
    local val=$(oracle_query_raw "$1" "system" | tr -d '[:space:]')
    if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "999"; fi
}

# 1. Audit Table Verification
AUDIT_TABLE_EXISTS=false
AUDIT_ROW_COUNT=0
AUDIT_CATEGORIES=0

TBL_CHECK=$(get_numeric "SELECT COUNT(*) FROM all_tables WHERE owner = 'COURT_ADMIN' AND table_name = 'DATA_QUALITY_ISSUES';")
if [ "$TBL_CHECK" -gt 0 ]; then
    AUDIT_TABLE_EXISTS=true
    AUDIT_ROW_COUNT=$(get_numeric "SELECT COUNT(*) FROM court_admin.data_quality_issues;")
    AUDIT_CATEGORIES=$(get_numeric "SELECT COUNT(DISTINCT issue_category) FROM court_admin.data_quality_issues;")
fi

# 2. Category 1: Orphans (Initial: 5 hearings, 4 attorneys)
ORPHAN_HEARINGS=$(get_numeric "SELECT COUNT(*) FROM court_admin.hearings WHERE case_id NOT IN (SELECT case_id FROM court_admin.cases);")
INVALID_ATTORNEYS=$(get_numeric "SELECT COUNT(*) FROM court_admin.case_parties WHERE attorney_id IS NOT NULL AND attorney_id NOT IN (SELECT attorney_id FROM court_admin.attorneys);")

# 3. Category 2: Temporal Violations (Initial: 8 hearings, 4 cases)
TEMPORAL_HEARINGS=$(get_numeric "SELECT COUNT(*) FROM court_admin.hearings h JOIN court_admin.cases c ON h.case_id = c.case_id WHERE h.hearing_date < c.filing_date;")
TEMPORAL_CASES=$(get_numeric "SELECT COUNT(*) FROM court_admin.cases WHERE disposition_date < filing_date;")

# 4. Category 3: Status Inconsistencies (Initial: 6 closed/future, 4 open/disp)
CLOSED_FUTURE=$(get_numeric "SELECT COUNT(*) FROM court_admin.cases c JOIN court_admin.hearings h ON c.case_id = h.case_id WHERE c.status = 'CLOSED' AND h.hearing_date > SYSDATE AND h.status != 'CANCELLED';")
OPEN_DISP=$(get_numeric "SELECT COUNT(*) FROM court_admin.cases WHERE status IN ('OPEN', 'ACTIVE') AND disposition IS NOT NULL;")

# 5. Category 4: Duplicates (Initial: 3 duplicate pairs -> 3 need 'DUPLICATE' status)
DUPLICATE_FLAGS=$(get_numeric "SELECT COUNT(*) FROM court_admin.cases WHERE status = 'DUPLICATE';")

# 6. Category 5: Fee Anomalies (Initial: 3 overpayments, 5 stale unpaid)
OVERPAYMENTS=$(get_numeric "SELECT COUNT(*) FROM court_admin.fees WHERE paid_amount > amount;")
STALE_UNPAID=$(get_numeric "SELECT COUNT(*) FROM court_admin.fees f JOIN court_admin.cases c ON f.case_id = c.case_id WHERE f.status = 'UNPAID' AND c.status = 'CLOSED' AND c.disposition_date < SYSDATE - 90;")
WAIVED_FEES=$(get_numeric "SELECT COUNT(*) FROM court_admin.fees WHERE status = 'WAIVED';")

# 7. CASE_INTEGRITY_VW Verification
VW_EXISTS=false
VW_ROWS=999
VW_CHECK=$(get_numeric "SELECT COUNT(*) FROM all_views WHERE owner = 'COURT_ADMIN' AND view_name = 'CASE_INTEGRITY_VW';")
if [ "$VW_CHECK" -gt 0 ]; then
    VW_EXISTS=true
    # Safe execution in case the view is invalid
    VW_ROWS_RES=$(oracle_query_raw "BEGIN EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM court_admin.case_integrity_vw'; EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('999'); END;" "system" | tr -d '[:space:]')
    if [[ "$VW_ROWS_RES" =~ ^[0-9]+$ ]]; then VW_ROWS=$VW_ROWS_RES; else VW_ROWS=999; fi
    # Fallback if block fails
    if [ "$VW_ROWS" = "999" ]; then
        VW_ROWS=$(get_numeric "SELECT COUNT(*) FROM court_admin.case_integrity_vw;" 2>/dev/null || echo "999")
    fi
fi

# 8. Triggers
TRIGGER_COUNT=$(get_numeric "SELECT COUNT(*) FROM all_triggers WHERE owner = 'COURT_ADMIN';")

# 9. CSV Report
CSV_EXISTS="false"
CSV_SIZE="0"
CSV_CONTENT_VALID="false"
if [ -f "/home/ga/court_audit_report.csv" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "/home/ga/court_audit_report.csv")
    if grep -qiE "orphan|temporal|status|duplicate|fee" "/home/ga/court_audit_report.csv"; then
        CSV_CONTENT_VALID="true"
    fi
fi

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "audit_table_exists": $AUDIT_TABLE_EXISTS,
    "audit_row_count": $AUDIT_ROW_COUNT,
    "audit_categories": $AUDIT_CATEGORIES,
    "orphan_hearings_remaining": $ORPHAN_HEARINGS,
    "invalid_attorneys_remaining": $INVALID_ATTORNEYS,
    "temporal_hearings_remaining": $TEMPORAL_HEARINGS,
    "temporal_cases_remaining": $TEMPORAL_CASES,
    "closed_future_remaining": $CLOSED_FUTURE,
    "open_disp_remaining": $OPEN_DISP,
    "duplicate_flags_set": $DUPLICATE_FLAGS,
    "overpayments_remaining": $OVERPAYMENTS,
    "stale_unpaid_remaining": $STALE_UNPAID,
    "waived_fees_set": $WAIVED_FEES,
    "view_exists": $VW_EXISTS,
    "view_rows": $VW_ROWS,
    "trigger_count": $TRIGGER_COUNT,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_content_valid": $CSV_CONTENT_VALID,
    $GUI_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/court_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/court_audit_result.json
chmod 666 /tmp/court_audit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/court_audit_result.json"
cat /tmp/court_audit_result.json

echo "=== Export Complete ==="