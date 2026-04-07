#!/bin/bash
echo "=== Exporting Sensor Noise Characterization Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/sensor_noise_start_ts 2>/dev/null || echo "0")
INITIAL_CMDS=$(cat /tmp/sensor_noise_initial_cmds 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/noise_characterization.json"

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

# Query current command counts to check if agent violated quiescent constraint
C1=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
C2=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
C3=$(cosmos_api "get_cmd_cnt" '"INST","NOOP"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
C4=$(cosmos_api "get_cmd_cnt" '"INST","SETPARAMS"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

C1=${C1:-0}; C2=${C2:-0}; C3=${C3:-0}; C4=${C4:-0}
FINAL_CMDS=$((C1 + C2 + C3 + C4))

echo "Initial command count: $INITIAL_CMDS"
echo "Final command count: $FINAL_CMDS"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/sensor_noise_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/sensor_noise_end.png 2>/dev/null || true

# Export results to JSON
cat > /tmp/sensor_noise_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_cmd_count": $INITIAL_CMDS,
    "final_cmd_count": $FINAL_CMDS
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="