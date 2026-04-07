#!/bin/bash
echo "=== Exporting Assembly Line Pattern Detection Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

# Helper function to get full view text directly using dbms_metadata
get_view_ddl() {
    local view_name="$1"
    sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << EOSQL
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 32767 LONG 2000000 LONGCHUNKSIZE 2000000
SELECT DBMS_METADATA.GET_DDL('VIEW', '$view_name', 'PROD_ENGINEER') FROM DUAL;
EXIT;
EOSQL
}

# Helper function to get materialized view DDL
get_mview_ddl() {
    local mv_name="$1"
    sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << EOSQL
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 32767 LONG 2000000 LONGCHUNKSIZE 2000000
SELECT DBMS_METADATA.GET_DDL('MATERIALIZED_VIEW', '$mv_name', 'PROD_ENGINEER') FROM DUAL;
EXIT;
EOSQL
}

# --- 1. CASCADE_FAILURES_VW ---
CASCADE_EXISTS=false
CASCADE_HAS_MATCH=false
CASCADE_ROWS=0

C_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='PROD_ENGINEER' AND view_name='CASCADE_FAILURES_VW';" "system" | tr -d '[:space:]')
if [ "${C_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CASCADE_EXISTS=true
    C_DDL=$(get_view_ddl "CASCADE_FAILURES_VW" | tr '[:upper:]' '[:lower:]')
    if echo "$C_DDL" | grep -q "match_recognize"; then
        CASCADE_HAS_MATCH=true
    fi
    C_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM prod_engineer.cascade_failures_vw;" "prod_engineer" "ProdEng2024" | tr -d '[:space:]')
    if [[ "$C_ROWS" =~ ^[0-9]+$ ]]; then CASCADE_ROWS=$C_ROWS; fi
fi

# --- 2. QUALITY_DEGRADATION_VW ---
QUALITY_EXISTS=false
QUALITY_HAS_MATCH=false
QUALITY_ROWS=0

Q_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='PROD_ENGINEER' AND view_name='QUALITY_DEGRADATION_VW';" "system" | tr -d '[:space:]')
if [ "${Q_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    QUALITY_EXISTS=true
    Q_DDL=$(get_view_ddl "QUALITY_DEGRADATION_VW" | tr '[:upper:]' '[:lower:]')
    if echo "$Q_DDL" | grep -q "match_recognize"; then
        QUALITY_HAS_MATCH=true
    fi
    Q_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM prod_engineer.quality_degradation_vw;" "prod_engineer" "ProdEng2024" | tr -d '[:space:]')
    if [[ "$Q_ROWS" =~ ^[0-9]+$ ]]; then QUALITY_ROWS=$Q_ROWS; fi
fi

# --- 3. SHORT_RUN_CYCLES_VW ---
SHORT_RUN_EXISTS=false
SHORT_RUN_HAS_MATCH=false
SHORT_RUN_ROWS=0

S_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='PROD_ENGINEER' AND view_name='SHORT_RUN_CYCLES_VW';" "system" | tr -d '[:space:]')
if [ "${S_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SHORT_RUN_EXISTS=true
    S_DDL=$(get_view_ddl "SHORT_RUN_CYCLES_VW" | tr '[:upper:]' '[:lower:]')
    if echo "$S_DDL" | grep -q "match_recognize"; then
        SHORT_RUN_HAS_MATCH=true
    fi
    S_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM prod_engineer.short_run_cycles_vw;" "prod_engineer" "ProdEng2024" | tr -d '[:space:]')
    if [[ "$S_ROWS" =~ ^[0-9]+$ ]]; then SHORT_RUN_ROWS=$S_ROWS; fi
fi

# --- 4. PATTERN_RESULTS table ---
PATTERN_ROWS=0
PATTERN_TYPES=0
P_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM prod_engineer.pattern_results;" "system" | tr -d '[:space:]')
if [[ "$P_ROWS" =~ ^[0-9]+$ ]]; then PATTERN_ROWS=$P_ROWS; fi
PT_ROWS=$(oracle_query_raw "SELECT COUNT(DISTINCT pattern_type) FROM prod_engineer.pattern_results;" "system" | tr -d '[:space:]')
if [[ "$PT_ROWS" =~ ^[0-9]+$ ]]; then PATTERN_TYPES=$PT_ROWS; fi

# --- 5. PROC_DAILY_PATTERN_SCAN ---
PROC_EXISTS=false
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner='PROD_ENGINEER' AND object_name='PROC_DAILY_PATTERN_SCAN';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS=true
fi

# --- 6. PATTERN_SUMMARY_MV ---
MV_EXISTS=false
MV_HAS_ROLLUP=false
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner='PROD_ENGINEER' AND mview_name='PATTERN_SUMMARY_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MV_EXISTS=true
    MV_DDL=$(get_mview_ddl "PATTERN_SUMMARY_MV" | tr '[:upper:]' '[:lower:]')
    if echo "$MV_DDL" | grep -q "rollup"; then
        MV_HAS_ROLLUP=true
    fi
fi

# --- 7. CSV Export ---
CSV_PATH="/home/ga/pattern_summary.csv"
CSV_EXISTS="false"
CSV_SIZE="0"
CSV_MODIFIED_DURING="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED_DURING="true"
    fi
fi

# --- GUI Evidence ---
GUI_EVIDENCE=$(collect_gui_evidence)

# Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cascade_vw_exists": $CASCADE_EXISTS,
    "cascade_has_match": $CASCADE_HAS_MATCH,
    "cascade_rows": $CASCADE_ROWS,
    "quality_vw_exists": $QUALITY_EXISTS,
    "quality_has_match": $QUALITY_HAS_MATCH,
    "quality_rows": $QUALITY_ROWS,
    "short_run_vw_exists": $SHORT_RUN_EXISTS,
    "short_run_has_match": $SHORT_RUN_HAS_MATCH,
    "short_run_rows": $SHORT_RUN_ROWS,
    "pattern_results_rows": $PATTERN_ROWS,
    "pattern_results_types": $PATTERN_TYPES,
    "proc_exists": $PROC_EXISTS,
    "mv_exists": $MV_EXISTS,
    "mv_has_rollup": $MV_HAS_ROLLUP,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    "csv_modified_during_task": $CSV_MODIFIED_DURING,
    $GUI_EVIDENCE
}
EOF

rm -f /tmp/pattern_detection_result.json 2>/dev/null || sudo rm -f /tmp/pattern_detection_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pattern_detection_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/pattern_detection_result.json
chmod 666 /tmp/pattern_detection_result.json 2>/dev/null || sudo chmod 666 /tmp/pattern_detection_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/pattern_detection_result.json"
cat /tmp/pattern_detection_result.json
echo "=== Export complete ==="