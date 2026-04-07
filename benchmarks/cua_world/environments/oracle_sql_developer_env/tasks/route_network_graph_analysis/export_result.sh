#!/bin/bash
# Export results for Route Network Graph Analysis task
echo "=== Exporting Route Network results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE closing anything
take_screenshot /tmp/task_final.png

# Collect GUI Evidence using utility
GUI_EVIDENCE=$(collect_gui_evidence)

# Initialize output JSON structure parts
REACH_VIEW_EXISTS="false"
REACH_HAS_ROWS="false"
REACH_USES_RECURSIVE="false"

SP_FUNC_EXISTS="false"
SP_TEST_RESULT="ERROR"

HC_MV_EXISTS="false"
HC_HAS_ROWS="false"

RG_VIEW_EXISTS="false"
RG_HAS_ROWS="false"

GC_FUNC_EXISTS="false"
GC_TEST_RESULT="ERROR"

RD_VIEW_EXISTS="false"

ANOMALY_TBL_EXISTS="false"
ANOMALY_PROC_EXISTS="false"
ANOMALY_HAS_ROWS="false"

# 1. Check Reachability View
RV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ROUTE_ANALYST' AND view_name = 'REACHABLE_FROM_ORD_VW';" "system" | tr -d '[:space:]')
if [ "${RV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    REACH_VIEW_EXISTS="true"
    RV_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM route_analyst.REACHABLE_FROM_ORD_VW;" "system" | tr -d '[:space:]')
    if [ "${RV_ROWS:-0}" -gt 0 ] 2>/dev/null; then
        REACH_HAS_ROWS="true"
    fi
    # Check for WITH...CYCLE or CONNECT BY
    RV_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'ROUTE_ANALYST' AND view_name = 'REACHABLE_FROM_ORD_VW';" "system" 2>/dev/null)
    if echo "$RV_TEXT" | grep -qiE "CYCLE|CONNECT\s+BY" 2>/dev/null; then
        REACH_USES_RECURSIVE="true"
    fi
fi

# 2. Check Shortest Path Function
SP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'ROUTE_ANALYST' AND object_name = 'FIND_SHORTEST_PATH';" "system" | tr -d '[:space:]')
if [ "${SP_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SP_FUNC_EXISTS="true"
    # Test function ORD -> LAX (Should be ORD->DFW->LAX or ORD->DEN->LAX)
    SP_TEST=$(oracle_query_raw "BEGIN DBMS_OUTPUT.PUT_LINE(route_analyst.FIND_SHORTEST_PATH('ORD', 'LAX')); EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('ERROR'); END;" "system" 2>/dev/null | grep -v "^$" | head -1)
    if [ -n "$SP_TEST" ]; then
        SP_TEST_RESULT="$SP_TEST"
    fi
fi

# 3. Check Hub Centrality MV
HC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'ROUTE_ANALYST' AND mview_name = 'HUB_CENTRALITY_MV';" "system" | tr -d '[:space:]')
if [ "${HC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    HC_MV_EXISTS="true"
    HC_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM route_analyst.HUB_CENTRALITY_MV;" "system" | tr -d '[:space:]')
    if [ "${HC_ROWS:-0}" -gt 0 ] 2>/dev/null; then
        HC_HAS_ROWS="true"
    fi
fi

# 4. Check Route Gap View
RG_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ROUTE_ANALYST' AND view_name = 'ROUTE_GAP_ANALYSIS_VW';" "system" | tr -d '[:space:]')
if [ "${RG_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    RG_VIEW_EXISTS="true"
    RG_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM route_analyst.ROUTE_GAP_ANALYSIS_VW;" "system" | tr -d '[:space:]')
    if [ "${RG_ROWS:-0}" -gt 0 ] 2>/dev/null; then
        RG_HAS_ROWS="true"
    fi
fi

# 5. Check Great Circle Function
GC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'ROUTE_ANALYST' AND object_name = 'CALC_GREAT_CIRCLE_KM';" "system" | tr -d '[:space:]')
if [ "${GC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    GC_FUNC_EXISTS="true"
    # Test function JFK -> LAX (Expected ~3975 km)
    GC_TEST=$(oracle_query_raw "BEGIN DBMS_OUTPUT.PUT_LINE(ROUND(route_analyst.CALC_GREAT_CIRCLE_KM(40.6398, -73.7789, 33.9425, -118.4081))); EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('ERROR'); END;" "system" 2>/dev/null | grep -v "^$" | head -1)
    if [ -n "$GC_TEST" ]; then
        GC_TEST_RESULT="$GC_TEST"
    fi
fi

RD_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ROUTE_ANALYST' AND view_name = 'ROUTE_DISTANCE_VW';" "system" | tr -d '[:space:]')
if [ "${RD_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    RD_VIEW_EXISTS="true"
fi

# 6. Check Anomaly Detection
AT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'ROUTE_ANALYST' AND table_name = 'ROUTE_ANOMALIES';" "system" | tr -d '[:space:]')
if [ "${AT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ANOMALY_TBL_EXISTS="true"
    AT_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM route_analyst.ROUTE_ANOMALIES WHERE anomaly_type = 'ASYMMETRIC';" "system" | tr -d '[:space:]')
    if [ "${AT_ROWS:-0}" -gt 0 ] 2>/dev/null; then
        ANOMALY_HAS_ROWS="true"
    fi
fi

AP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'ROUTE_ANALYST' AND object_name = 'PROC_DETECT_ASYMMETRIC_ROUTES';" "system" | tr -d '[:space:]')
if [ "${AP_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ANOMALY_PROC_EXISTS="true"
fi

# Construct Result JSON
TEMP_JSON=$(mktemp /tmp/route_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "reachability": {
        "view_exists": $REACH_VIEW_EXISTS,
        "has_rows": $REACH_HAS_ROWS,
        "uses_recursive": $REACH_USES_RECURSIVE
    },
    "shortest_path": {
        "func_exists": $SP_FUNC_EXISTS,
        "test_result": "$(echo "$SP_TEST_RESULT" | sed 's/"/\\"/g')"
    },
    "hub_centrality": {
        "mv_exists": $HC_MV_EXISTS,
        "has_rows": $HC_HAS_ROWS
    },
    "route_gap": {
        "view_exists": $RG_VIEW_EXISTS,
        "has_rows": $RG_HAS_ROWS
    },
    "great_circle": {
        "func_exists": $GC_FUNC_EXISTS,
        "test_result": "$(echo "$GC_TEST_RESULT" | sed 's/"/\\"/g')",
        "view_exists": $RD_VIEW_EXISTS
    },
    "anomalies": {
        "table_exists": $ANOMALY_TBL_EXISTS,
        "proc_exists": $ANOMALY_PROC_EXISTS,
        "has_rows": $ANOMALY_HAS_ROWS
    },
    $GUI_EVIDENCE
}
EOF

# Move to target location securely
rm -f /tmp/route_network_result.json 2>/dev/null || sudo rm -f /tmp/route_network_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/route_network_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/route_network_result.json
chmod 666 /tmp/route_network_result.json 2>/dev/null || sudo chmod 666 /tmp/route_network_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/route_network_result.json"
cat /tmp/route_network_result.json
echo "=== Export complete ==="