#!/bin/bash
echo "=== Exporting Shift Handover Report Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/shift_handover_report_start_ts 2>/dev/null || echo "0")
INITIAL_COLLECT_COUNT=$(cat /tmp/shift_handover_report_initial_collect_count 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/handover_report.json"

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

# Query current command count to verify agent sent COLLECT
CURRENT_COLLECT_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

# Capture ground truth telemetry values for plausibility check
# Suppress errors if API not responding perfectly during teardown
GT_TEMP1=$(cosmos_tlm "INST HEALTH_STATUS TEMP1" 2>/dev/null || echo "0.0")
GT_TEMP2=$(cosmos_tlm "INST HEALTH_STATUS TEMP2" 2>/dev/null || echo "0.0")
GT_TEMP3=$(cosmos_tlm "INST HEALTH_STATUS TEMP3" 2>/dev/null || echo "0.0")
GT_TEMP4=$(cosmos_tlm "INST HEALTH_STATUS TEMP4" 2>/dev/null || echo "0.0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/shift_handover_report_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/shift_handover_report_end.png 2>/dev/null || true

# Save export metadata as JSON
cat > /tmp/shift_handover_report_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_collect_count": $INITIAL_COLLECT_COUNT,
    "current_collect_count": $CURRENT_COLLECT_COUNT,
    "ground_truth_telemetry": {
        "temp1": "$GT_TEMP1",
        "temp2": "$GT_TEMP2",
        "temp3": "$GT_TEMP3",
        "temp4": "$GT_TEMP4"
    }
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "Initial COLLECT: $INITIAL_COLLECT_COUNT"
echo "Current COLLECT: $CURRENT_COLLECT_COUNT"
echo "=== Export Complete ==="