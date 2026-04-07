#!/bin/bash
echo "=== Exporting Maritime AIS Port Congestion results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize metrics
PING_ZONES_VW_EXISTS=false
VESSEL_STAYS_VW_EXISTS=false
PORT_CALLS_VW_EXISTS=false
CONGESTION_MV_EXISTS=false
JOB_EXISTS=false
CSV_EXISTS=false
CSV_SIZE=0

MMSI1001_STAYS_COUNT=0
MMSI1003_STAYS_COUNT=99
PORT_CALLS_COUNT=0
ROLLUP_ROWS=0

# --- Check Views ---
PZ_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'MARINE_OPS' AND view_name = 'PING_ZONES_VW';" "system" | tr -d '[:space:]')
if [ "${PZ_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PING_ZONES_VW_EXISTS=true
fi

VS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'MARINE_OPS' AND view_name = 'VESSEL_STAYS_VW';" "system" | tr -d '[:space:]')
if [ "${VS_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VESSEL_STAYS_VW_EXISTS=true
    
    # Check Gaps & Islands Logic
    # MMSI 1001 should have exactly 3 stays (2 Anchorage, 1 Terminal) if gaps & islands is correct. 
    # If they just grouped by mmsi, zone_id, they will have 2 stays.
    MMSI1001_STAYS_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM marine_ops.vessel_stays_vw WHERE mmsi = 1001;" "system" | tr -d '[:space:]')
    MMSI1001_STAYS_COUNT=${MMSI1001_STAYS_COUNT:-0}
    
    # MMSI 1003 has 1 ping, should be filtered out.
    MMSI1003_STAYS_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM marine_ops.vessel_stays_vw WHERE mmsi = 1003;" "system" | tr -d '[:space:]')
    MMSI1003_STAYS_COUNT=${MMSI1003_STAYS_COUNT:-99}
fi

PC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'MARINE_OPS' AND view_name = 'PORT_CALLS_VW';" "system" | tr -d '[:space:]')
if [ "${PC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PORT_CALLS_VW_EXISTS=true
    
    # Check logic: Should be 1 valid port call (MMSI 1001). MMSI 1002 fails 24hr check.
    PORT_CALLS_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM marine_ops.port_calls_vw;" "system" | tr -d '[:space:]')
    PORT_CALLS_COUNT=${PORT_CALLS_COUNT:-0}
fi

MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'MARINE_OPS' AND mview_name = 'WEEKLY_CONGESTION_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CONGESTION_MV_EXISTS=true
    
    # Check ROLLUP logic (rows where vessel_type or iso_week is NULL)
    ROLLUP_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM marine_ops.weekly_congestion_mv WHERE vessel_type IS NULL;" "system" | tr -d '[:space:]')
    ROLLUP_ROWS=${ROLLUP_ROWS:-0}
fi

# --- Check Job ---
JOB_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_scheduler_jobs WHERE owner = 'MARINE_OPS' AND job_name = 'REFRESH_CONGESTION_DATA';" "system" | tr -d '[:space:]')
if [ "${JOB_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    JOB_EXISTS=true
fi

# --- Check CSV ---
CSV_PATH="/home/ga/Documents/exports/congestion_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# --- Get GUI usage evidence ---
GUI_JSON=$(collect_gui_evidence)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "ping_zones_vw_exists": $PING_ZONES_VW_EXISTS,
    "vessel_stays_vw_exists": $VESSEL_STAYS_VW_EXISTS,
    "mmsi1001_stays_count": $MMSI1001_STAYS_COUNT,
    "mmsi1003_stays_count": $MMSI1003_STAYS_COUNT,
    "port_calls_vw_exists": $PORT_CALLS_VW_EXISTS,
    "port_calls_count": $PORT_CALLS_COUNT,
    "congestion_mv_exists": $CONGESTION_MV_EXISTS,
    "rollup_rows": $ROLLUP_ROWS,
    "job_exists": $JOB_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    ${GUI_JSON}
}
EOF

# Safe file replacement
rm -f /tmp/maritime_ais_result.json 2>/dev/null || sudo rm -f /tmp/maritime_ais_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/maritime_ais_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/maritime_ais_result.json
chmod 666 /tmp/maritime_ais_result.json 2>/dev/null || sudo chmod 666 /tmp/maritime_ais_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/maritime_ais_result.json"
cat /tmp/maritime_ais_result.json
echo "=== Export complete ==="