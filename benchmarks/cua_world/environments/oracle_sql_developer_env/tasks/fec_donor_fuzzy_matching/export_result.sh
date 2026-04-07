#!/bin/bash
echo "=== Exporting Campaign Finance Deduplication Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

MATCH_PAIRS_EXISTS=false
MATCH_PAIRS_COUNT=0
CANONICAL_MAP_EXISTS=false
ARNOLD_MAPPED=0
GEORGE_MAPPED=0
ALL_MAPPED=false
MV_EXISTS=false
MV_TOTAL_MATCH=false
VIOLATIONS_EXISTS=false
VIOLATIONS_COUNT=0
VIOLATOR_101=0
VIOLATOR_301=0
CSV_EXISTS=false
CSV_SIZE=0

# DONOR_MATCH_PAIRS
MP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner='ELECTIONS_ADMIN' AND table_name='DONOR_MATCH_PAIRS';" "system" | tr -d '[:space:]')
if [ "${MP_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MATCH_PAIRS_EXISTS=true
    MATCH_PAIRS_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM elections_admin.donor_match_pairs;" "system" | tr -d '[:space:]')
    MATCH_PAIRS_COUNT=${MATCH_PAIRS_COUNT:-0}
fi

# DONOR_CANONICAL_MAP
CM_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='ELECTIONS_ADMIN' AND view_name='DONOR_CANONICAL_MAP';" "system" | tr -d '[:space:]')
if [ "${CM_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CANONICAL_MAP_EXISTS=true
    ARNOLD_MAPPED=$(oracle_query_raw "SELECT COUNT(*) FROM elections_admin.donor_canonical_map WHERE donor_id IN (101,102,103) AND canonical_id = 101;" "system" | tr -d '[:space:]')
    GEORGE_MAPPED=$(oracle_query_raw "SELECT COUNT(*) FROM elections_admin.donor_canonical_map WHERE donor_id IN (201,202,203) AND canonical_id = 201;" "system" | tr -d '[:space:]')
    ARNOLD_MAPPED=${ARNOLD_MAPPED:-0}
    GEORGE_MAPPED=${GEORGE_MAPPED:-0}
    if [ "$ARNOLD_MAPPED" -eq 3 ] && [ "$GEORGE_MAPPED" -eq 3 ]; then
        ALL_MAPPED=true
    fi
fi

# CONSOLIDATED_DONOR_FINANCIALS_MV
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner='ELECTIONS_ADMIN' AND mview_name='CONSOLIDATED_DONOR_FINANCIALS_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MV_EXISTS=true
    TOTAL_MV=$(oracle_query_raw "SELECT SUM(total_contributions) FROM elections_admin.consolidated_donor_financials_mv;" "system" | tr -d '[:space:]')
    TOTAL_RAW=$(oracle_query_raw "SELECT SUM(transaction_amt) FROM elections_admin.contributions;" "system" | tr -d '[:space:]')
    if [ "${TOTAL_MV:-0}" = "${TOTAL_RAW:-1}" ]; then
        MV_TOTAL_MATCH=true
    fi
fi

# VIOLATION_ALERTS
VA_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner='ELECTIONS_ADMIN' AND table_name='VIOLATION_ALERTS';" "system" | tr -d '[:space:]')
if [ "${VA_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VIOLATIONS_EXISTS=true
    VIOLATIONS_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM elections_admin.violation_alerts;" "system" | tr -d '[:space:]')
    VIOLATIONS_COUNT=${VIOLATIONS_COUNT:-0}
    VIOLATOR_101=$(oracle_query_raw "SELECT COUNT(*) FROM elections_admin.violation_alerts WHERE canonical_id = 101;" "system" | tr -d '[:space:]')
    VIOLATOR_301=$(oracle_query_raw "SELECT COUNT(*) FROM elections_admin.violation_alerts WHERE canonical_id = 301;" "system" | tr -d '[:space:]')
    VIOLATOR_101=${VIOLATOR_101:-0}
    VIOLATOR_301=${VIOLATOR_301:-0}
fi

# CSV Export
CSV_PATH="/home/ga/Documents/exports/limit_violators.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "match_pairs_exists": $MATCH_PAIRS_EXISTS,
    "match_pairs_count": $MATCH_PAIRS_COUNT,
    "canonical_map_exists": $CANONICAL_MAP_EXISTS,
    "arnold_mapped": $ARNOLD_MAPPED,
    "george_mapped": $GEORGE_MAPPED,
    "all_mapped": $ALL_MAPPED,
    "mv_exists": $MV_EXISTS,
    "mv_total_match": $MV_TOTAL_MATCH,
    "violations_exists": $VIOLATIONS_EXISTS,
    "violations_count": $VIOLATIONS_COUNT,
    "violator_101": $VIOLATOR_101,
    "violator_301": $VIOLATOR_301,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

# Move temp file to expected location securely
rm -f /tmp/fec_donor_result.json 2>/dev/null || sudo rm -f /tmp/fec_donor_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fec_donor_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fec_donor_result.json
chmod 666 /tmp/fec_donor_result.json 2>/dev/null || sudo chmod 666 /tmp/fec_donor_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/fec_donor_result.json"
cat /tmp/fec_donor_result.json
echo "=== Export complete ==="