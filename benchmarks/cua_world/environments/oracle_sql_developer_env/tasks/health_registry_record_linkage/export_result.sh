#!/bin/bash
# Export results for Health Registry Record Linkage
echo "=== Exporting Health Registry Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Init variables
VIEW_EXISTS="false"
VIEW_TEXT=""
UTL_MATCH_JW="false"
UTL_MATCH_ED="false"
SEQUENCE_EXISTS="false"
SEQUENCE_START_VALID="false"
TABLE_EXISTS="false"
TABLE_ROW_COUNT=0
CSV_EXISTS="false"
CSV_MODIFIED_DURING_TASK="false"
CSV_SIZE=0

# 1. Check View
VIEW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'HIE_ADMIN' AND view_name = 'PROBABLE_MATCHES_VW';" "system" "OraclePassword123" | tr -d '[:space:]')
if [ "${VIEW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VIEW_EXISTS="true"
    VIEW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'HIE_ADMIN' AND view_name = 'PROBABLE_MATCHES_VW';" "system" "OraclePassword123" 2>/dev/null)
    
    # Check for specific UTL_MATCH functions in the view text
    if echo "$VIEW_TEXT" | grep -qiE "UTL_MATCH\.JARO_WINKLER_SIMILARITY"; then
        UTL_MATCH_JW="true"
    fi
    if echo "$VIEW_TEXT" | grep -qiE "UTL_MATCH\.EDIT_DISTANCE"; then
        UTL_MATCH_ED="true"
    fi
fi

# 2. Check Sequence
SEQ_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_sequences WHERE sequence_owner = 'HIE_ADMIN' AND sequence_name = 'MPI_SEQ';" "system" "OraclePassword123" | tr -d '[:space:]')
if [ "${SEQ_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SEQUENCE_EXISTS="true"
    SEQ_LAST=$(oracle_query_raw "SELECT last_number FROM all_sequences WHERE sequence_owner = 'HIE_ADMIN' AND sequence_name = 'MPI_SEQ';" "system" "OraclePassword123" | tr -d '[:space:]')
    if [ "${SEQ_LAST:-0}" -ge 1000000 ] 2>/dev/null; then
        SEQUENCE_START_VALID="true"
    fi
fi

# 3. Check Table and Data
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'HIE_ADMIN' AND table_name = 'MPI_CROSSWALK';" "system" "OraclePassword123" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    TABLE_EXISTS="true"
    TABLE_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM hie_admin.mpi_crosswalk;" "system" "OraclePassword123" | tr -d '[:space:]')
    TABLE_ROW_COUNT=${TABLE_ROW_COUNT:-0}
fi

# 4. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/mpi_crosswalk.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED_DURING_TASK="true"
    fi
fi

# 5. Check GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON Export
TEMP_JSON=$(mktemp /tmp/hie_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "view_exists": $VIEW_EXISTS,
    "utl_match_jaro_winkler_used": $UTL_MATCH_JW,
    "utl_match_edit_distance_used": $UTL_MATCH_ED,
    "sequence_exists": $SEQUENCE_EXISTS,
    "sequence_start_valid": $SEQUENCE_START_VALID,
    "table_exists": $TABLE_EXISTS,
    "table_row_count": $TABLE_ROW_COUNT,
    "csv_exists": $CSV_EXISTS,
    "csv_modified_during_task": $CSV_MODIFIED_DURING_TASK,
    "csv_size_bytes": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

# Make readable for verifier
rm -f /tmp/health_registry_result.json 2>/dev/null || sudo rm -f /tmp/health_registry_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/health_registry_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/health_registry_result.json
chmod 666 /tmp/health_registry_result.json 2>/dev/null || sudo chmod 666 /tmp/health_registry_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/health_registry_result.json"
cat /tmp/health_registry_result.json
echo "=== Export Complete ==="