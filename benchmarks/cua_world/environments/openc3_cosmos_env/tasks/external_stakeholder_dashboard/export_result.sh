#!/bin/bash
echo "=== Exporting External Stakeholder Dashboard Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/dashboard_start_ts 2>/dev/null || echo "0")
INITIAL_CMD_CNT=$(cat /tmp/dashboard_initial_cmd_cnt 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/stakeholder_dashboard.html"

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

# Query current CMD_ACPT_CNT from telemetry to verify command was actually sent in COSMOS
CURRENT_CMD_CNT=$(cosmos_tlm "INST HEALTH_STATUS CMD_ACPT_CNT" 2>/dev/null || echo "0")
if [ -z "$CURRENT_CMD_CNT" ] || [ "$CURRENT_CMD_CNT" = "null" ]; then
    CURRENT_CMD_CNT="0"
fi

echo "Initial CMD_ACPT_CNT: $INITIAL_CMD_CNT"
echo "Current CMD_ACPT_CNT: $CURRENT_CMD_CNT"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/dashboard_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/dashboard_end.png 2>/dev/null || true

cat > /tmp/dashboard_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_cmd_cnt": $INITIAL_CMD_CNT,
    "current_cmd_cnt": $CURRENT_CMD_CNT
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="