#!/bin/bash
echo "=== Exporting Implicit State Deduction Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/implicit_state_deduction_start_ts 2>/dev/null || echo "0")
INITIAL_CMD_COUNT=$(cat /tmp/implicit_state_deduction_initial_cmd_count 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/state_deduction.json"

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

# Query current COLLECT command count to verify agent sent a command
CURRENT_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial COLLECT count: $INITIAL_CMD_COUNT"
echo "Current COLLECT count: $CURRENT_CMD_COUNT"

# Query current live COLLECTS telemetry value (to bound authenticity of agent data)
LIVE_COLLECTS=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
echo "Current Live COLLECTS telemetry: $LIVE_COLLECTS"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/implicit_state_deduction_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/implicit_state_deduction_end.png 2>/dev/null || true

cat > /tmp/implicit_state_deduction_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_cmd_count": $INITIAL_CMD_COUNT,
    "current_cmd_count": $CURRENT_CMD_COUNT,
    "live_collects_value": $LIVE_COLLECTS
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="