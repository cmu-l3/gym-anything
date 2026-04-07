#!/bin/bash
echo "=== Exporting Command Uplink Optimization Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/command_uplink_optimization_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/optimized_schedule.json"

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

# Query current counts to verify agent sent the correct number of commands
CURRENT_COLLECTS=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
CURRENT_CMD=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

INITIAL_COLLECTS=$(cat /tmp/command_uplink_optimization_initial_collects 2>/dev/null || echo "0")
INITIAL_CMD=$(cat /tmp/command_uplink_optimization_initial_cmd 2>/dev/null || echo "0")

echo "Initial CMD: $INITIAL_CMD | Current CMD: $CURRENT_CMD"
echo "Initial TLM: $INITIAL_COLLECTS | Current TLM: $CURRENT_COLLECTS"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/command_uplink_optimization_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/command_uplink_optimization_end.png 2>/dev/null || true

cat > /tmp/command_uplink_optimization_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_collects": $INITIAL_COLLECTS,
    "current_collects": $CURRENT_COLLECTS,
    "initial_cmd": $INITIAL_CMD,
    "current_cmd": $CURRENT_CMD
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="