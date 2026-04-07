#!/bin/bash
echo "=== Exporting E-Commerce RFM Segmentation results ==="

source /workspace/scripts/task_utils.sh

# Final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize flags
CLEAN_VW_EXISTS="false"
METRICS_VW_EXISTS="false"
SCORES_VW_EXISTS="false"
NTILE_USED="false"
SEGMENTS_TBL_EXISTS="false"
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_SIZE="0"

# 1. Check CLEAN_TRANSACTIONS_VW
RES=$(oracle_query_raw "SELECT COUNT(*) FROM dba_views WHERE owner='RETAIL_BI' AND view_name='CLEAN_TRANSACTIONS_VW';" "system" | tr -d '[:space:]')
if [ "${RES:-0}" -gt 0 ] 2>/dev/null; then CLEAN_VW_EXISTS="true"; fi

# 2. Check RFM_METRICS_VW
RES=$(oracle_query_raw "SELECT COUNT(*) FROM dba_views WHERE owner='RETAIL_BI' AND view_name='RFM_METRICS_VW';" "system" | tr -d '[:space:]')
if [ "${RES:-0}" -gt 0 ] 2>/dev/null; then METRICS_VW_EXISTS="true"; fi

# 3. Check RFM_SCORES_VW
RES=$(oracle_query_raw "SELECT COUNT(*) FROM dba_views WHERE owner='RETAIL_BI' AND view_name='RFM_SCORES_VW';" "system" | tr -d '[:space:]')
if [ "${RES:-0}" -gt 0 ] 2>/dev/null; then SCORES_VW_EXISTS="true"; fi

# 4. Check CUSTOMER_SEGMENTS Table
RES=$(oracle_query_raw "SELECT COUNT(*) FROM dba_tables WHERE owner='RETAIL_BI' AND table_name='CUSTOMER_SEGMENTS';" "system" | tr -d '[:space:]')
if [ "${RES:-0}" -gt 0 ] 2>/dev/null; then SEGMENTS_TBL_EXISTS="true"; fi

# 5. Check NTILE usage specifically inside the RFM_SCORES_VW
if [ "$SCORES_VW_EXISTS" = "true" ]; then
    VW_TEXT=$(sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 32767 LONG 32767
SELECT text FROM dba_views WHERE owner='RETAIL_BI' AND view_name='RFM_SCORES_VW';
EXIT;
EOSQL
    )
    if echo "$VW_TEXT" | grep -qi "NTILE"; then
        NTILE_USED="true"
    fi
fi

# 6. Check CSV Export (Anti-gaming via timestamp checking)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/exports/at_risk_vips.csv"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# 7. Collect GUI telemetry
if type collect_gui_evidence &>/dev/null; then
    GUI_EVIDENCE=$(collect_gui_evidence)
else
    # Fallback string
    GUI_EVIDENCE='"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "sqldev_oracle_sessions": 0}'
fi

# Build JSON payload
TEMP_JSON=$(mktemp /tmp/rfm_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "clean_vw_exists": $CLEAN_VW_EXISTS,
    "metrics_vw_exists": $METRICS_VW_EXISTS,
    "scores_vw_exists": $SCORES_VW_EXISTS,
    "ntile_used": $NTILE_USED,
    "segments_tbl_exists": $SEGMENTS_TBL_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_size": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

# Move and set permissions
rm -f /tmp/rfm_result.json 2>/dev/null || sudo rm -f /tmp/rfm_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/rfm_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/rfm_result.json
chmod 666 /tmp/rfm_result.json 2>/dev/null || sudo chmod 666 /tmp/rfm_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported successfully to /tmp/rfm_result.json"
cat /tmp/rfm_result.json