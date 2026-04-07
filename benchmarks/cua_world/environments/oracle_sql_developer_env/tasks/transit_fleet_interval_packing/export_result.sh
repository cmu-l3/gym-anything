#!/bin/bash
echo "=== Exporting Transit Fleet Interval Packing results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize flags
DOWNTIME_BLOCKS_EXISTS=false
AVAILABILITY_VW_EXISTS=false
ALERT_TBL_EXISTS=false
ALERT_PROC_EXISTS=false
GUI_USED=false

RAW_LOG_COUNT=0
PACKED_BLOCK_COUNT=0
OVERLAP_COUNT=-1
ALERT_COUNT=0
CSV_EXISTS=false
CSV_SIZE=0
CSV_MODIFIED=false

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# --- 1. Check DOWNTIME_BLOCKS_VW ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'TRANSIT_OPS' AND view_name = 'DOWNTIME_BLOCKS_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    DOWNTIME_BLOCKS_EXISTS=true
    
    # Check counts
    RAW_LOG_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM transit_ops.maintenance_logs WHERE end_time IS NOT NULL;" "system" | tr -d '[:space:]')
    PACKED_BLOCK_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM transit_ops.downtime_blocks_vw;" "system" | tr -d '[:space:]')
    
    # Verify no overlaps remain using self-join
    OVERLAP_COUNT=$(oracle_query_raw "
    SELECT COUNT(*) FROM transit_ops.downtime_blocks_vw a
    JOIN transit_ops.downtime_blocks_vw b
      ON a.locomotive_id = b.locomotive_id
     AND a.block_start_time < b.block_start_time
    WHERE a.block_end_time > b.block_start_time;" "system" | tr -d '[:space:]')
fi

# --- 2. Check FLEET_AVAILABILITY_VW ---
AVAIL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'TRANSIT_OPS' AND view_name = 'FLEET_AVAILABILITY_VW';" "system" | tr -d '[:space:]')
if [ "${AVAIL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    AVAILABILITY_VW_EXISTS=true
fi

# --- 3. Check Alert Infrastructure ---
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'TRANSIT_OPS' AND table_name = 'MAINTENANCE_ALERTS';" "system" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ALERT_TBL_EXISTS=true
    # Count rows
    ALERT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM transit_ops.maintenance_alerts;" "system" | tr -d '[:space:]')
fi

PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'TRANSIT_OPS' AND object_name = 'PROC_FLAG_STUCK_LOCOMOTIVES';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ALERT_PROC_EXISTS=true
fi

# --- 4. Check CSV Export ---
CSV_PATH="/home/ga/Documents/exports/locomotive_availability.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED=true
    fi
fi

# --- 5. GUI Evidence ---
GUI_EVIDENCE=$(collect_gui_evidence)

# --- Construct JSON Output ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "downtime_blocks_exists": $DOWNTIME_BLOCKS_EXISTS,
    "raw_log_count": ${RAW_LOG_COUNT:-0},
    "packed_block_count": ${PACKED_BLOCK_COUNT:-0},
    "overlap_count": ${OVERLAP_COUNT:--1},
    "availability_vw_exists": $AVAILABILITY_VW_EXISTS,
    "alert_tbl_exists": $ALERT_TBL_EXISTS,
    "alert_proc_exists": $ALERT_PROC_EXISTS,
    "alert_count": ${ALERT_COUNT:-0},
    "csv_exists": $CSV_EXISTS,
    "csv_modified": $CSV_MODIFIED,
    "csv_size": $CSV_SIZE,
    "task_start": $TASK_START,
    "gui_evidence": {$(echo "$GUI_EVIDENCE" | grep -v '^{|}$')}
}
EOF

# Move JSON to final location safely
rm -f /tmp/transit_fleet_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/transit_fleet_result.json
chmod 666 /tmp/transit_fleet_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/transit_fleet_result.json"
cat /tmp/transit_fleet_result.json
echo "=== Export complete ==="