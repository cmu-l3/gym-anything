#!/bin/bash
echo "=== Exporting Command Boundary Enforcement Audit Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/command_boundary_start_ts 2>/dev/null || echo "0")
INITIAL_CMD_COUNT=$(cat /tmp/command_boundary_initial_cmd_count 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/boundary_audit.json"

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_MTIME=0

if [ -f "$OUTPUT" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
fi

# Query current COLLECT command count to verify the valid command was actually sent to the system
CURRENT_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial COLLECT count: $INITIAL_CMD_COUNT"
echo "Current COLLECT count: $CURRENT_CMD_COUNT"

# Take final screenshot
take_screenshot /tmp/command_boundary_end.png

# Create JSON result
cat > /tmp/command_boundary_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_cmd_count": $INITIAL_CMD_COUNT,
    "current_cmd_count": $CURRENT_CMD_COUNT
}
EOF

# Ensure correct permissions
chmod 666 /tmp/command_boundary_result.json 2>/dev/null || true

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="