#!/bin/bash
echo "=== Exporting Simulated Transient Anomaly Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/simulated_transient_anomaly_start_ts 2>/dev/null || echo "0")
INITIAL_CLEAR_COUNT=$(cat /tmp/simulated_transient_anomaly_initial_clear 2>/dev/null || echo "0")
INITIAL_YELLOW_HIGH=$(cat /tmp/simulated_transient_anomaly_initial_limit 2>/dev/null || echo "null")
OUTPUT="/home/ga/Desktop/simulated_anomaly_report.json"

FILE_EXISTS=false
FILE_IS_NEW=false
FILE_MTIME=0

if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
fi

# Query current CLEAR command count
CURRENT_CLEAR_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

# Query current YELLOW_HIGH limit
LIMITS_JSON=$(cosmos_api "get_limits" '"INST","HEALTH_STATUS","TEMP1"' 2>/dev/null)
CURRENT_YELLOW_HIGH=$(echo "$LIMITS_JSON" | jq -r '.result[2] // "null"' 2>/dev/null || echo "null")

echo "Initial CLEAR count: $INITIAL_CLEAR_COUNT | Current: $CURRENT_CLEAR_COUNT"
echo "Initial YELLOW_HIGH: $INITIAL_YELLOW_HIGH | Current: $CURRENT_YELLOW_HIGH"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/simulated_transient_anomaly_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/simulated_transient_anomaly_end.png 2>/dev/null || true

cat > /tmp/simulated_transient_anomaly_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_clear_count": $INITIAL_CLEAR_COUNT,
    "current_clear_count": $CURRENT_CLEAR_COUNT,
    "initial_yellow_high": "$INITIAL_YELLOW_HIGH",
    "current_yellow_high": "$CURRENT_YELLOW_HIGH"
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="