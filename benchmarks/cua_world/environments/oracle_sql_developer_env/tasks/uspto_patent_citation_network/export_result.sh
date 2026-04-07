#!/bin/bash
# Export results for USPTO Patent Citation Network Analysis task
echo "=== Exporting USPTO Patent Analysis results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize output variables
TREE_VW_EXISTS="false"
TREE_VW_RECURSIVE="false"
TREE_VW_ROWS=0
SELF_CITE_VW_EXISTS="false"
SELF_CITE_IBM_PCT=0
CYCLE_TIME_VW_EXISTS="false"
CYCLE_TIME_PCT_CONT="false"
INFLUENTIAL_MV_EXISTS="false"
INFLUENTIAL_ROWS=0
CSV_EXISTS="false"
CSV_SIZE=0
CSV_CREATED_DURING="false"

# ---------------------------------------------------------
# 1. Check FORWARD_CITATION_TREE_VW
# ---------------------------------------------------------
if [ "$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='USPTO_ANALYST' AND view_name='FORWARD_CITATION_TREE_VW';" "system")" -gt 0 ] 2>/dev/null; then
    TREE_VW_EXISTS="true"
    TREE_VW_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM uspto_analyst.forward_citation_tree_vw;" "system" 2>/dev/null | tr -d '[:space:]' || echo "0")
    
    # Check if CONNECT BY or recursive WITH was used
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='USPTO_ANALYST' AND view_name='FORWARD_CITATION_TREE_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "CONNECT\s+BY|WITH.*AS.*UNION\s+ALL" 2>/dev/null; then
        TREE_VW_RECURSIVE="true"
    fi
fi

# ---------------------------------------------------------
# 2. Check SELF_CITATION_METRICS_VW
# ---------------------------------------------------------
if [ "$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='USPTO_ANALYST' AND view_name='SELF_CITATION_METRICS_VW';" "system")" -gt 0 ] 2>/dev/null; then
    SELF_CITE_VW_EXISTS="true"
    # Check IBM's self-citation percentage
    IBM_PCT=$(oracle_query_raw "SELECT NVL(ROUND(self_citation_pct),0) FROM uspto_analyst.self_citation_metrics_vw WHERE organization LIKE '%International Business Machines%';" "system" 2>/dev/null | tr -d '[:space:]')
    if [[ "$IBM_PCT" =~ ^[0-9]+$ ]]; then
        SELF_CITE_IBM_PCT=$IBM_PCT
    fi
fi

# ---------------------------------------------------------
# 3. Check TECH_CYCLE_TIME_VW
# ---------------------------------------------------------
if [ "$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='USPTO_ANALYST' AND view_name='TECH_CYCLE_TIME_VW';" "system")" -gt 0 ] 2>/dev/null; then
    CYCLE_TIME_VW_EXISTS="true"
    # Check if PERCENTILE_CONT was used
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='USPTO_ANALYST' AND view_name='TECH_CYCLE_TIME_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "PERCENTILE_CONT\s*\(\s*0\.5\s*\)" 2>/dev/null; then
        CYCLE_TIME_PCT_CONT="true"
    fi
fi

# ---------------------------------------------------------
# 4. Check TOP_INFLUENTIAL_PATENTS_MV
# ---------------------------------------------------------
if [ "$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner='USPTO_ANALYST' AND mview_name='TOP_INFLUENTIAL_PATENTS_MV';" "system")" -gt 0 ] 2>/dev/null; then
    INFLUENTIAL_MV_EXISTS="true"
    INFLUENTIAL_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM uspto_analyst.top_influential_patents_mv;" "system" 2>/dev/null | tr -d '[:space:]' || echo "0")
fi

# ---------------------------------------------------------
# 5. Check CSV Export
# ---------------------------------------------------------
CSV_PATH="/home/ga/Documents/exports/self_citation_anomalies.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp to prevent gaming
    TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
fi

# ---------------------------------------------------------
# GUI Evidence
# ---------------------------------------------------------
GUI_EVIDENCE=$(collect_gui_evidence)

# ---------------------------------------------------------
# Create JSON Result
# ---------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "tree_vw_exists": $TREE_VW_EXISTS,
    "tree_vw_recursive": $TREE_VW_RECURSIVE,
    "tree_vw_rows": ${TREE_VW_ROWS:-0},
    "self_cite_vw_exists": $SELF_CITE_VW_EXISTS,
    "self_cite_ibm_pct": ${SELF_CITE_IBM_PCT:-0},
    "cycle_time_vw_exists": $CYCLE_TIME_VW_EXISTS,
    "cycle_time_pct_cont": $CYCLE_TIME_PCT_CONT,
    "influential_mv_exists": $INFLUENTIAL_MV_EXISTS,
    "influential_rows": ${INFLUENTIAL_ROWS:-0},
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    "csv_created_during": $CSV_CREATED_DURING,
    ${GUI_EVIDENCE}
}
EOF

rm -f /tmp/uspto_result.json 2>/dev/null || sudo rm -f /tmp/uspto_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/uspto_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/uspto_result.json
chmod 666 /tmp/uspto_result.json 2>/dev/null || sudo chmod 666 /tmp/uspto_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/uspto_result.json"
cat /tmp/uspto_result.json
echo "=== Export complete ==="