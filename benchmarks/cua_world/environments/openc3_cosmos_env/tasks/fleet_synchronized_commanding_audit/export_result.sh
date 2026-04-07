#!/bin/bash
echo "=== Exporting Fleet Synchronized Commanding Audit Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/fleet_command_start_ts 2>/dev/null || echo "0")
INITIAL_INST=$(cat /tmp/fleet_command_initial_inst 2>/dev/null || echo "0")
INITIAL_INST2=$(cat /tmp/fleet_command_initial_inst2 2>/dev/null || echo "0")

OUTPUT="/home/ga/Desktop/fleet_command_report.json"

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

# Query current command acceptance counts to prove agent executed commands
FINAL_INST=$(cosmos_tlm "INST HEALTH_STATUS CMD_ACPT_CNT" 2>/dev/null || echo "0")
FINAL_INST2=$(cosmos_tlm "INST2 HEALTH_STATUS CMD_ACPT_CNT" 2>/dev/null || echo "0")

echo "Final INST CMD_ACPT_CNT: $FINAL_INST"
echo "Final INST2 CMD_ACPT_CNT: $FINAL_INST2"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/fleet_command_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/fleet_command_end.png 2>/dev/null || true

# Serialize data for the Python verifier
cat > /tmp/fleet_command_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_inst_count": "$INITIAL_INST",
    "initial_inst2_count": "$INITIAL_INST2",
    "final_inst_count": "$FINAL_INST",
    "final_inst2_count": "$FINAL_INST2"
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="