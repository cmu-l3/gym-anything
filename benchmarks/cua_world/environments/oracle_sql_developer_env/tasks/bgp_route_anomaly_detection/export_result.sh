#!/bin/bash
# Export results for BGP Route Anomaly Detection task
echo "=== Exporting BGP Route Anomaly Detection results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize tracking variables
FUNC_EXISTS="false"
FUNC_VALID="false"
FUNC_TEST_RESULT="0"
IP_RANGES_VW_EXISTS="false"
BOGON_LEAKS_TBL_EXISTS="false"
BOGON_COUNT="0"
HIJACK_VW_EXISTS="false"
HIJACK_COUNT="0"
FOOTPRINT_MV_EXISTS="false"
FOOTPRINT_15169="0"
FOOTPRINT_3356="0"
PROC_EXISTS="false"
JOB_EXISTS="false"
CSV_EXISTS="false"
CSV_SIZE="0"
TASK_START_TIME=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# --- 1. Check Function ---
FUNC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'NET_ADMIN' AND object_name = 'FUNC_IPV4_TO_INT' AND object_type = 'FUNCTION';" "system" | tr -d '[:space:]')
if [ "${FUNC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FUNC_EXISTS="true"
    VALID_CHECK=$(oracle_query_raw "SELECT status FROM all_objects WHERE owner = 'NET_ADMIN' AND object_name = 'FUNC_IPV4_TO_INT' AND object_type = 'FUNCTION';" "system" | tr -d '[:space:]')
    if [ "$VALID_CHECK" = "VALID" ]; then
        FUNC_VALID="true"
        # Test the function logic: 192.168.1.5 -> 3232235777
        FUNC_TEST_RESULT=$(oracle_query_raw "SELECT net_admin.func_ipv4_to_int('192.168.1.5') FROM DUAL;" "system" | tr -d '[:space:]')
        FUNC_TEST_RESULT=${FUNC_TEST_RESULT:-0}
    fi
fi

# --- 2. Check IP Ranges View ---
RANGES_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'NET_ADMIN' AND view_name = 'BGP_PREFIX_RANGES_VW';" "system" | tr -d '[:space:]')
if [ "${RANGES_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    IP_RANGES_VW_EXISTS="true"
fi

# --- 3. Check Bogon Leaks Table ---
BOGON_TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'NET_ADMIN' AND table_name = 'BOGON_LEAKS';" "system" | tr -d '[:space:]')
if [ "${BOGON_TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    BOGON_LEAKS_TBL_EXISTS="true"
    BOGON_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM net_admin.bogon_leaks;" "system" | tr -d '[:space:]')
    BOGON_COUNT=${BOGON_COUNT:-0}
fi

# --- 4. Check Route Hijacks View ---
HIJACK_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'NET_ADMIN' AND view_name = 'ROUTE_HIJACK_SUSPECTS_VW';" "system" | tr -d '[:space:]')
if [ "${HIJACK_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    HIJACK_VW_EXISTS="true"
    HIJACK_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM net_admin.route_hijack_suspects_vw;" "system" | tr -d '[:space:]')
    HIJACK_COUNT=${HIJACK_COUNT:-0}
fi

# --- 5. Check ASN Footprint MV ---
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'NET_ADMIN' AND mview_name = 'ASN_FOOTPRINT_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FOOTPRINT_MV_EXISTS="true"
    # Check deduplication logic by looking at known ASN footprints
    # 15169 should be exactly 65536
    FOOTPRINT_15169=$(oracle_query_raw "SELECT total_unique_ips FROM net_admin.asn_footprint_mv WHERE origin_asn = 15169;" "system" | tr -d '[:space:]')
    FOOTPRINT_15169=${FOOTPRINT_15169:-0}
    # 3356 should be exactly 1,114,112
    FOOTPRINT_3356=$(oracle_query_raw "SELECT total_unique_ips FROM net_admin.asn_footprint_mv WHERE origin_asn = 3356;" "system" | tr -d '[:space:]')
    FOOTPRINT_3356=${FOOTPRINT_3356:-0}
fi

# --- 6. Check Procedure and Scheduler Job ---
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'NET_ADMIN' AND object_name = 'PROC_REFRESH_FOOTPRINT';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS="true"
fi

JOB_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_scheduler_jobs WHERE owner = 'NET_ADMIN' AND job_name = 'BGP_FOOTPRINT_JOB';" "system" | tr -d '[:space:]')
if [ "${JOB_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    JOB_EXISTS="true"
fi

# --- 7. Check CSV Export ---
CSV_PATH="/home/ga/Documents/exports/bgp_hijack_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START_TIME" ]; then
        CSV_EXISTS="true"
        CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    fi
fi

# --- Collect GUI Evidence ---
GUI_EVIDENCE=$(collect_gui_evidence)

# --- Construct JSON Output ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "func_exists": $FUNC_EXISTS,
    "func_valid": $FUNC_VALID,
    "func_test_result": "$FUNC_TEST_RESULT",
    "ip_ranges_vw_exists": $IP_RANGES_VW_EXISTS,
    "bogon_leaks_tbl_exists": $BOGON_LEAKS_TBL_EXISTS,
    "bogon_count": $BOGON_COUNT,
    "hijack_vw_exists": $HIJACK_VW_EXISTS,
    "hijack_count": $HIJACK_COUNT,
    "footprint_mv_exists": $FOOTPRINT_MV_EXISTS,
    "footprint_15169": "$FOOTPRINT_15169",
    "footprint_3356": "$FOOTPRINT_3356",
    "proc_exists": $PROC_EXISTS,
    "job_exists": $JOB_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

# Move securely
rm -f /tmp/bgp_anomaly_result.json 2>/dev/null || sudo rm -f /tmp/bgp_anomaly_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/bgp_anomaly_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/bgp_anomaly_result.json
chmod 666 /tmp/bgp_anomaly_result.json 2>/dev/null || sudo chmod 666 /tmp/bgp_anomaly_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/bgp_anomaly_result.json"
cat /tmp/bgp_anomaly_result.json