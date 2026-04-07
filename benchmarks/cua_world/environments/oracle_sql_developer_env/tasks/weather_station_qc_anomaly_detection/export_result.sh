#!/bin/bash
# Export results for Weather Station QC Anomaly Detection task
echo "=== Exporting Weather QC results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png ga

# Initialize result variables
QC_RESULTS_EXISTS="false"
STUCK_SENSOR_FLAGS=0
IMPOSSIBLE_VALUE_FLAGS=0
IDW_FUNC_EXISTS="false"
HAVERSINE_USED="false"
ANOMALY_VW_EXISTS="false"
STDDEV_USED="false"
QC_MV_EXISTS="false"
CSV_EXISTS="false"
CSV_SIZE=0

# --- Check QC_RESULTS table and row counts ---
QC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'WEATHER_ANALYST' AND table_name = 'QC_RESULTS';" "system" | tr -d '[:space:]')
if [ "${QC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    QC_RESULTS_EXISTS="true"
    
    STUCK_SENSOR_FLAGS=$(oracle_query_raw "SELECT COUNT(*) FROM weather_analyst.qc_results WHERE flag_type = 'STUCK_SENSOR';" "system" | tr -d '[:space:]')
    STUCK_SENSOR_FLAGS=${STUCK_SENSOR_FLAGS:-0}
    
    IMPOSSIBLE_VALUE_FLAGS=$(oracle_query_raw "SELECT COUNT(*) FROM weather_analyst.qc_results WHERE flag_type = 'IMPOSSIBLE_VALUE';" "system" | tr -d '[:space:]')
    IMPOSSIBLE_VALUE_FLAGS=${IMPOSSIBLE_VALUE_FLAGS:-0}
fi

# --- Check FUNC_IDW_ESTIMATE ---
FUNC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'WEATHER_ANALYST' AND object_name = 'FUNC_IDW_ESTIMATE' AND object_type = 'FUNCTION';" "system" | tr -d '[:space:]')
if [ "${FUNC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    IDW_FUNC_EXISTS="true"
    
    # Check for Haversine components (SIN, COS, ACOS) in function source
    FUNC_TEXT=$(oracle_query_raw "SELECT text FROM all_source WHERE owner = 'WEATHER_ANALYST' AND name = 'FUNC_IDW_ESTIMATE' AND type = 'FUNCTION';" "system" 2>/dev/null)
    if echo "$FUNC_TEXT" | grep -qiE "ACOS\s*\(|COS\s*\(|SIN\s*\(" 2>/dev/null; then
        HAVERSINE_USED="true"
    fi
fi

# --- Check CLIMATE_ANOMALY_VW ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'WEATHER_ANALYST' AND view_name = 'CLIMATE_ANOMALY_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ANOMALY_VW_EXISTS="true"
    
    # Check for STDDEV in view source
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'WEATHER_ANALYST' AND view_name = 'CLIMATE_ANOMALY_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "STDDEV" 2>/dev/null; then
        STDDEV_USED="true"
    fi
fi

# --- Check QUALITY_CONTROLLED_OBS_MV ---
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'WEATHER_ANALYST' AND mview_name = 'QUALITY_CONTROLLED_OBS_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    QC_MV_EXISTS="true"
fi

# --- Check CSV export ---
CSV_PATH="/home/ga/climate_summary.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# Collect GUI evidence using existing utility function
GUI_JSON=$(collect_gui_evidence)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "qc_results_exists": $QC_RESULTS_EXISTS,
    "stuck_sensor_flags": $STUCK_SENSOR_FLAGS,
    "impossible_value_flags": $IMPOSSIBLE_VALUE_FLAGS,
    "idw_func_exists": $IDW_FUNC_EXISTS,
    "haversine_used": $HAVERSINE_USED,
    "anomaly_vw_exists": $ANOMALY_VW_EXISTS,
    "stddev_used": $STDDEV_USED,
    "qc_mv_exists": $QC_MV_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    $GUI_JSON
}
EOF

# Move to final location securely
rm -f /tmp/weather_qc_result.json 2>/dev/null || sudo rm -f /tmp/weather_qc_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/weather_qc_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/weather_qc_result.json
chmod 666 /tmp/weather_qc_result.json 2>/dev/null || sudo chmod 666 /tmp/weather_qc_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/weather_qc_result.json"
cat /tmp/weather_qc_result.json
echo "=== Export complete ==="