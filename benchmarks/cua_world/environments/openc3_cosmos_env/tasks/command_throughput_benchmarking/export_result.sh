#!/bin/bash
echo "=== Exporting Command Throughput Benchmarking Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/throughput_benchmark_start_ts 2>/dev/null || echo "0")
INITIAL_CMD_COUNT=$(cat /tmp/throughput_benchmark_initial_cmd_count 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/throughput_benchmark.json"

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

# Query current COLLECT command count to verify agent actually sent commands
CURRENT_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial COLLECT count: $INITIAL_CMD_COUNT"
echo "Current COLLECT count: $CURRENT_CMD_COUNT"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/throughput_benchmark_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/throughput_benchmark_end.png 2>/dev/null || true

cat > /tmp/throughput_benchmark_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_cmd_count": $INITIAL_CMD_COUNT,
    "current_cmd_count": $CURRENT_CMD_COUNT
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="