#!/bin/bash
# Export results for Transit GTFS Bunching Analysis task
echo "=== Exporting Transit GTFS Bunching results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize vars
FUNC_EXISTS=false
FUNC_TEST_VAL=""
FUNC_CORRECT=false
ADHERENCE_VW_EXISTS=false
BUNCHING_MV_EXISTS=false
LAG_USED=false
SCORECARD_TBL_EXISTS=false
PROC_EXISTS=false
SCORECARD_ROWS=0
SCORECARD_BUNCHING_COUNT=0
CSV_EXISTS=false
CSV_SIZE=0

# --- Check Function GTFS_TO_MINUTES ---
FUNC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'TRANSIT_ADMIN' AND object_name = 'GTFS_TO_MINUTES' AND object_type = 'FUNCTION';" "system" | tr -d '[:space:]')
if [ "${FUNC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FUNC_EXISTS=true
    
    # Test function logic
    FUNC_TEST_VAL=$(oracle_query_raw "SELECT transit_admin.gtfs_to_minutes('26:45:15') FROM DUAL;" "system" 2>/dev/null | tr -d '[:space:]')
    
    # Accept 1605.25 or 1605 (if they rounded)
    if [ "$FUNC_TEST_VAL" = "1605.25" ] || [ "$FUNC_TEST_VAL" = "1605" ]; then
        FUNC_CORRECT=true
    fi
fi

# --- Check SCHEDULE_ADHERENCE_VW ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'TRANSIT_ADMIN' AND view_name = 'SCHEDULE_ADHERENCE_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ADHERENCE_VW_EXISTS=true
fi

# --- Check BUNCHING_EVENTS_MV ---
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'TRANSIT_ADMIN' AND mview_name = 'BUNCHING_EVENTS_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    BUNCHING_MV_EXISTS=true
    
    # Check if LAG was used
    MV_TEXT=$(oracle_query_raw "SELECT query FROM all_mviews WHERE owner = 'TRANSIT_ADMIN' AND mview_name = 'BUNCHING_EVENTS_MV';" "system" 2>/dev/null)
    if echo "$MV_TEXT" | grep -qiE "LAG\s*\(" 2>/dev/null; then
        LAG_USED=true
    fi
fi

# Fallback: check all source for LAG usage
if [ "$LAG_USED" = "false" ]; then
    SRC_TEXT=$(oracle_query_raw "SELECT text FROM all_source WHERE owner = 'TRANSIT_ADMIN' ORDER BY name, type, line;" "system" 2>/dev/null)
    if echo "$SRC_TEXT" | grep -qiE "LAG\s*\(" 2>/dev/null; then
        LAG_USED=true
    fi
fi

# --- Check ROUTE_SCORECARD table ---
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'TRANSIT_ADMIN' AND table_name = 'ROUTE_SCORECARD';" "system" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SCORECARD_TBL_EXISTS=true
    SCORECARD_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM transit_admin.route_scorecard;" "system" | tr -d '[:space:]')
    SCORECARD_ROWS=${SCORECARD_ROWS:-0}
    
    # Check if route 10 has bunching events identified
    SCORECARD_BUNCHING_COUNT=$(oracle_query_raw "SELECT NVL(SUM(bunching_events_count), 0) FROM transit_admin.route_scorecard WHERE route_id = 'R10';" "system" | tr -d '[:space:]')
    SCORECARD_BUNCHING_COUNT=${SCORECARD_BUNCHING_COUNT:-0}
fi

# --- Check PROC_GENERATE_SCORECARD ---
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'TRANSIT_ADMIN' AND object_name = 'PROC_GENERATE_SCORECARD';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS=true
fi

# --- Check CSV export ---
CSV_PATH="/home/ga/Documents/exports/route_scorecard.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# --- Get GUI usage evidence ---
GUI_EVIDENCE=$(collect_gui_evidence || echo '"gui_evidence": {}')
if [ -z "$GUI_EVIDENCE" ]; then GUI_EVIDENCE='"gui_evidence": {}'; fi

# --- Generate JSON ---
TEMP_JSON=$(mktemp /tmp/transit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "func_exists": $FUNC_EXISTS,
    "func_test_val": "$FUNC_TEST_VAL",
    "func_correct": $FUNC_CORRECT,
    "adherence_vw_exists": $ADHERENCE_VW_EXISTS,
    "bunching_mv_exists": $BUNCHING_MV_EXISTS,
    "lag_used": $LAG_USED,
    "scorecard_tbl_exists": $SCORECARD_TBL_EXISTS,
    "scorecard_rows": $SCORECARD_ROWS,
    "scorecard_bunching_count": $SCORECARD_BUNCHING_COUNT,
    "proc_exists": $PROC_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

# Save result
rm -f /tmp/transit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/transit_result.json
chmod 666 /tmp/transit_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Results:"
cat /tmp/transit_result.json