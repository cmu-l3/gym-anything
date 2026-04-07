#!/bin/bash
# Export script for Public Health Database Optimization task
echo "=== Exporting Public Health task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/task_end_screenshot.png

# Initialize evaluation flags
VC_EXISTS="false"
FBI_EXISTS="false"
FBI_EXPR=""
MLOG_EXISTS="false"
MLOG_ROWIDS="NO"
MLOG_SEQ="NO"
MLOG_NEW_VAL="NO"
MV_EXISTS="false"
MV_REFRESH=""
PEST_VIEW_EXISTS="false"
CHRONIC_VIEW_EXISTS="false"
CHRONIC_ROWS=0
CSV_EXISTS="false"
CSV_SIZE=0
FILE_CREATED_DURING_TASK="false"

# 1. Check Virtual Column
VC_CHECK=$(oracle_query_raw "SELECT virtual_column FROM all_tab_cols WHERE owner='HEALTH_ADMIN' AND table_name='FOOD_INSPECTIONS' AND column_name='INSPECTION_YEAR';" "system" | tr -d '[:space:]')
if [ "$VC_CHECK" = "YES" ]; then
    VC_EXISTS="true"
fi

# 2. Check Function-Based Index
FBI_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_indexes WHERE owner='HEALTH_ADMIN' AND index_name='IDX_FBI_DBA' AND index_type LIKE '%FUNCTION-BASED%';" "system" | tr -d '[:space:]')
if [ "${FBI_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FBI_EXISTS="true"
    FBI_EXPR=$(oracle_query_raw "SELECT column_expression FROM all_ind_expressions WHERE index_owner='HEALTH_ADMIN' AND index_name='IDX_FBI_DBA';" "system" | tr -d '\n\r' | sed 's/"//g')
fi

# 3. Check Materialized View Log
MLOG_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mlogs WHERE log_owner='HEALTH_ADMIN' AND master='FOOD_INSPECTIONS';" "system" | tr -d '[:space:]')
if [ "${MLOG_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MLOG_EXISTS="true"
    MLOG_ROWIDS=$(oracle_query_raw "SELECT rowids FROM all_mlogs WHERE log_owner='HEALTH_ADMIN' AND master='FOOD_INSPECTIONS';" "system" | tr -d '[:space:]')
    MLOG_SEQ=$(oracle_query_raw "SELECT sequence FROM all_mlogs WHERE log_owner='HEALTH_ADMIN' AND master='FOOD_INSPECTIONS';" "system" | tr -d '[:space:]')
    MLOG_NEW_VAL=$(oracle_query_raw "SELECT include_new_values FROM all_mlogs WHERE log_owner='HEALTH_ADMIN' AND master='FOOD_INSPECTIONS';" "system" | tr -d '[:space:]')
fi

# 4. Check Fast-Refresh Materialized View
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner='HEALTH_ADMIN' AND mview_name='MV_ZIP_STATS';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MV_EXISTS="true"
    MV_REFRESH=$(oracle_query_raw "SELECT refresh_method FROM all_mviews WHERE owner='HEALTH_ADMIN' AND mview_name='MV_ZIP_STATS';" "system" | tr -d '[:space:]')
fi

# 5. Check Pest View
PEST_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='HEALTH_ADMIN' AND view_name='PEST_VIOLATIONS_VW';" "system" | tr -d '[:space:]')
if [ "${PEST_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PEST_VIEW_EXISTS="true"
fi

# 6. Check Chronic Offender View
CHRONIC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='HEALTH_ADMIN' AND view_name='CHRONIC_FAILURES_VW';" "system" | tr -d '[:space:]')
if [ "${CHRONIC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CHRONIC_VIEW_EXISTS="true"
    CHRONIC_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM health_admin.chronic_failures_vw;" "system" | tr -d '[:space:]')
    CHRONIC_ROWS=${CHRONIC_ROWS:-0}
fi

# 7. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/chronic_offenders.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Get GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "vc_exists": $VC_EXISTS,
    "fbi_exists": $FBI_EXISTS,
    "fbi_expr": "$FBI_EXPR",
    "mlog_exists": $MLOG_EXISTS,
    "mlog_rowids": "$MLOG_ROWIDS",
    "mlog_seq": "$MLOG_SEQ",
    "mlog_new_val": "$MLOG_NEW_VAL",
    "mv_exists": $MV_EXISTS,
    "mv_refresh": "$MV_REFRESH",
    "pest_view_exists": $PEST_VIEW_EXISTS,
    "chronic_view_exists": $CHRONIC_VIEW_EXISTS,
    "chronic_rows": $CHRONIC_ROWS,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    $GUI_EVIDENCE
}
EOF

# Move securely
rm -f /tmp/public_health_result.json 2>/dev/null || sudo rm -f /tmp/public_health_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/public_health_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/public_health_result.json
chmod 666 /tmp/public_health_result.json 2>/dev/null || sudo chmod 666 /tmp/public_health_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/public_health_result.json"
cat /tmp/public_health_result.json
echo "=== Export Complete ==="