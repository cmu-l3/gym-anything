#!/bin/bash
echo "=== Exporting Asynchronous Telemetry Sensor Fusion Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/async_sensor_fusion_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/aligned_telemetry.json"

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_MTIME="0"

if [ -f "$OUTPUT" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
fi

# Query final received counts securely
get_tlm_count_final() {
    local target="$1"
    local packet="$2"
    local val
    val=$(cosmos_tlm "$target $packet RECEIVED_COUNT" 2>/dev/null | tr -d ' "\n\r')
    if [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "$val"
    else
        echo "999999999"
    fi
}

HS_FINAL=$(get_tlm_count_final "INST" "HEALTH_STATUS")
ADCS_FINAL=$(get_tlm_count_final "INST" "ADCS")

HS_INITIAL=$(cat /tmp/hs_initial_count 2>/dev/null || echo "0")
ADCS_INITIAL=$(cat /tmp/adcs_initial_count 2>/dev/null || echo "0")

echo "Final HS Count: $HS_FINAL"
echo "Final ADCS Count: $ADCS_FINAL"

take_screenshot /tmp/async_sensor_fusion_end.png 2>/dev/null || true

cat > /tmp/async_sensor_fusion_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "hs_initial": $HS_INITIAL,
    "hs_final": $HS_FINAL,
    "adcs_initial": $ADCS_INITIAL,
    "adcs_final": $ADCS_FINAL
}
EOF

echo "=== Export Complete ==="