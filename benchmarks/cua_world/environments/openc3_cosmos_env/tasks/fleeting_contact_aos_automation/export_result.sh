#!/bin/bash
echo "=== Exporting Fleeting Contact AOS Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_CMD_ACPT=$(cat /tmp/initial_cmd_acpt.txt 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/pass_capture.json"

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

# Get the ground truth timestamps from the background simulation
AOS_START_TIME=$(cat /tmp/aos_start.txt 2>/dev/null || echo "0")
AOS_END_TIME=$(cat /tmp/aos_end.txt 2>/dev/null || echo "0")
READY_SIGNAL=$( [ -f /tmp/ready_for_pass.txt ] && echo "true" || echo "false" )

# Allow telemetry to settle briefly before reading final state
sleep 2
CURRENT_CMD_ACPT=$(cosmos_tlm "INST HEALTH_STATUS CMD_ACPT_CNT" 2>/dev/null | sed 's/"//g' || echo "0")

echo "Initial CMD_ACPT_CNT: $INITIAL_CMD_ACPT"
echo "Current CMD_ACPT_CNT: $CURRENT_CMD_ACPT"
echo "AOS Start: $AOS_START_TIME"
echo "AOS End: $AOS_END_TIME"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Bundle result data
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_cmd_acpt": $INITIAL_CMD_ACPT,
    "current_cmd_acpt": $CURRENT_CMD_ACPT,
    "ready_signal_sent": $READY_SIGNAL,
    "aos_start_time": $AOS_START_TIME,
    "aos_end_time": $AOS_END_TIME
}
EOF

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export Complete ==="