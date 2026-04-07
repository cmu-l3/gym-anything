#!/bin/bash
echo "=== Exporting Transit Network Bunching Analysis Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# Custom query runner for the transit_admin schema
run_sql() {
    local query="$1"
    sudo docker exec -i oracle-xe sqlplus -s transit_admin/Transit2024@//localhost:1521/XEPDB1 << EOSQL 2>&1 | grep -v '^$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 32767
$query
EXIT;
EOSQL
}

# 2. Check the PARSE_GTFS_TIME function
FUNC_DAY=$(run_sql "SELECT EXTRACT(DAY FROM PARSE_GTFS_TIME('27:45:15')) FROM DUAL;" | grep -Eo '^[0-9]+' || echo "ERROR")
FUNC_HOUR=$(run_sql "SELECT EXTRACT(HOUR FROM PARSE_GTFS_TIME('27:45:15')) FROM DUAL;" | grep -Eo '^[0-9]+' || echo "ERROR")
FUNC_MIN=$(run_sql "SELECT EXTRACT(MINUTE FROM PARSE_GTFS_TIME('27:45:15')) FROM DUAL;" | grep -Eo '^[0-9]+' || echo "ERROR")

FUNC_CORRECT="false"
if [ "$FUNC_DAY" = "1" ] && [ "$FUNC_HOUR" = "3" ] && [ "$FUNC_MIN" = "45" ]; then
    FUNC_CORRECT="true"
fi

# 3. Check SEGMENT_RUN_TIMES_VW
SEGMENT_VW_EXISTS=$(run_sql "SELECT COUNT(*) FROM user_views WHERE view_name = 'SEGMENT_RUN_TIMES_VW';" | grep -Eo '^[0-9]+' || echo "0")
HAS_LEAD="false"
if [ "$SEGMENT_VW_EXISTS" = "1" ]; then
    SEGMENT_TEXT=$(run_sql "SELECT text FROM user_views WHERE view_name = 'SEGMENT_RUN_TIMES_VW';")
    if echo "$SEGMENT_TEXT" | grep -qi "LEAD"; then
        HAS_LEAD="true"
    fi
fi

# 4. Check BUNCHING_RISK_VW
BUNCHING_VW_EXISTS=$(run_sql "SELECT COUNT(*) FROM user_views WHERE view_name = 'BUNCHING_RISK_VW';" | grep -Eo '^[0-9]+' || echo "0")
HAS_LAG="false"
BUNCHING_ROWS="0"
if [ "$BUNCHING_VW_EXISTS" = "1" ]; then
    BUNCHING_TEXT=$(run_sql "SELECT text FROM user_views WHERE view_name = 'BUNCHING_RISK_VW';")
    if echo "$BUNCHING_TEXT" | grep -qi "LAG"; then
        HAS_LAG="true"
    fi
    BUNCHING_ROWS=$(run_sql "SELECT COUNT(*) FROM BUNCHING_RISK_VW;" | grep -Eo '^[0-9]+' || echo "0")
fi

# 5. Check ROUTE_PERFORMANCE_MV
ROUTE_MV_EXISTS=$(run_sql "SELECT COUNT(*) FROM user_mviews WHERE mview_name = 'ROUTE_PERFORMANCE_MV';" | grep -Eo '^[0-9]+' || echo "0")
ROUTE_MV_ROWS="0"
if [ "$ROUTE_MV_EXISTS" = "1" ]; then
    ROUTE_MV_ROWS=$(run_sql "SELECT COUNT(*) FROM ROUTE_PERFORMANCE_MV;" | grep -Eo '^[0-9]+' || echo "0")
fi

# 6. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/route_performance.csv"
CSV_EXISTS="false"
CSV_SIZE="0"
CSV_MODIFIED_DURING_TASK="false"
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -ge "$TASK_START" ]; then
        CSV_MODIFIED_DURING_TASK="true"
    fi
fi

# 7. Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# 8. Create JSON Output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "func_correct": $FUNC_CORRECT,
    "func_day_val": "$FUNC_DAY",
    "segment_vw_exists": $( [ "$SEGMENT_VW_EXISTS" = "1" ] && echo "true" || echo "false" ),
    "has_lead": $HAS_LEAD,
    "bunching_vw_exists": $( [ "$BUNCHING_VW_EXISTS" = "1" ] && echo "true" || echo "false" ),
    "has_lag": $HAS_LAG,
    "bunching_rows": $BUNCHING_ROWS,
    "route_mv_exists": $( [ "$ROUTE_MV_EXISTS" = "1" ] && echo "true" || echo "false" ),
    "route_mv_rows": $ROUTE_MV_ROWS,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    "csv_modified_during_task": $CSV_MODIFIED_DURING_TASK,
    $GUI_EVIDENCE
}
EOF

rm -f /tmp/transit_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/transit_task_result.json
chmod 666 /tmp/transit_task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Results saved to /tmp/transit_task_result.json"
cat /tmp/transit_task_result.json