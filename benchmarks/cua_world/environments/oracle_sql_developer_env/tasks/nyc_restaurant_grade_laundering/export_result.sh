#!/bin/bash
# Export results for NYC Restaurant Grade Laundering Detection task
echo "=== Exporting NYC Restaurant Audit Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize JSON vars
LIFECYCLE_MV_EXISTS=false
SUSPECT_VW_EXISTS=false
CHAINS_VW_EXISTS=false
REPORT_VW_EXISTS=false
UTL_MATCH_USED=false
CONNECT_BY_USED=false
CSV_EXISTS=false
CSV_SIZE=0
CHAIN1_CRITICALS=0
CHAIN2_CRITICALS=0

# --- Check 1: RESTAURANT_LIFECYCLES_MV ---
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'HEALTH_AUDITOR' AND mview_name = 'RESTAURANT_LIFECYCLES_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    LIFECYCLE_MV_EXISTS=true
fi

# --- Check 2: SUSPECT_TRANSITIONS_VW ---
VW1_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'HEALTH_AUDITOR' AND view_name = 'SUSPECT_TRANSITIONS_VW';" "system" | tr -d '[:space:]')
if [ "${VW1_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SUSPECT_VW_EXISTS=true
    
    # Check for UTL_MATCH usage in text
    VW1_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'HEALTH_AUDITOR' AND view_name = 'SUSPECT_TRANSITIONS_VW';" "system" 2>/dev/null)
    if echo "$VW1_TEXT" | grep -qiE "UTL_MATCH\.JARO_WINKLER_SIMILARITY" 2>/dev/null; then
        UTL_MATCH_USED=true
    fi
fi

# --- Check 3: LAUNDERING_CHAINS_VW ---
VW2_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'HEALTH_AUDITOR' AND view_name = 'LAUNDERING_CHAINS_VW';" "system" | tr -d '[:space:]')
if [ "${VW2_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CHAINS_VW_EXISTS=true
    
    # Check for Hierarchical query (CONNECT BY or Recursive CTE)
    VW2_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'HEALTH_AUDITOR' AND view_name = 'LAUNDERING_CHAINS_VW';" "system" 2>/dev/null)
    if echo "$VW2_TEXT" | grep -qiE "CONNECT\s+BY|SYS_CONNECT_BY_PATH|WITH.*AS\s*\(.*UNION\s+ALL" 2>/dev/null; then
        CONNECT_BY_USED=true
    fi
fi

# --- Check 4: CHRONIC_OFFENDERS_REPORT_VW ---
VW3_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'HEALTH_AUDITOR' AND view_name = 'CHRONIC_OFFENDERS_REPORT_VW';" "system" | tr -d '[:space:]')
if [ "${VW3_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    REPORT_VW_EXISTS=true
    
    # Check aggregated math for Known Seeded Chains
    # Chain 1 (root: 1001) should have 9 criticals.
    C1_CHECK=$(oracle_query_raw "SELECT combined_critical_violations FROM health_auditor.chronic_offenders_report_vw WHERE root_camis = 1001;" "system" | tr -d '[:space:]')
    CHAIN1_CRITICALS=${C1_CHECK:-0}
    
    # Chain 2 (root: 2001) should have 12 criticals.
    C2_CHECK=$(oracle_query_raw "SELECT combined_critical_violations FROM health_auditor.chronic_offenders_report_vw WHERE root_camis = 2001;" "system" | tr -d '[:space:]')
    CHAIN2_CRITICALS=${C2_CHECK:-0}
fi

# --- Check 5: CSV Export ---
CSV_PATH="/home/ga/Documents/exports/chronic_offenders.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# --- Check 6: GUI Usage ---
GUI_EVIDENCE=$(collect_gui_evidence)

# --- Compile JSON Output ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "lifecycle_mv_exists": $LIFECYCLE_MV_EXISTS,
    "suspect_vw_exists": $SUSPECT_VW_EXISTS,
    "chains_vw_exists": $CHAINS_VW_EXISTS,
    "report_vw_exists": $REPORT_VW_EXISTS,
    "utl_match_used": $UTL_MATCH_USED,
    "connect_by_used": $CONNECT_BY_USED,
    "chain1_criticals": $CHAIN1_CRITICALS,
    "chain2_criticals": $CHAIN2_CRITICALS,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

# Move temp file to final location safely
rm -f /tmp/restaurant_audit_result.json 2>/dev/null || sudo rm -f /tmp/restaurant_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/restaurant_audit_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/restaurant_audit_result.json
chmod 666 /tmp/restaurant_audit_result.json 2>/dev/null || sudo chmod 666 /tmp/restaurant_audit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/restaurant_audit_result.json"
cat /tmp/restaurant_audit_result.json
echo "=== Export Complete ==="