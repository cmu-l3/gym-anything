#!/bin/bash
echo "=== Exporting Schedule-Driven Command Execution Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/schedule_driven_command_execution_start_ts 2>/dev/null || echo "0")
SCRIPT_FILE="/home/ga/Desktop/pass_executor.py"
RECEIPT_FILE="/home/ga/Desktop/execution_receipt.json"

SCRIPT_EXISTS=false
RECEIPT_EXISTS=false
RECEIPT_MTIME=0

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS=true
fi

if [ -f "$RECEIPT_FILE" ]; then
    RECEIPT_EXISTS=true
    RECEIPT_MTIME=$(stat -c %Y "$RECEIPT_FILE" 2>/dev/null || echo "0")
fi

# Get current command counts
CUR_CLEAR=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
CUR_COLLECT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
CUR_ABORT=$(cosmos_api "get_cmd_cnt" '"INST","ABORT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

INIT_CLEAR=$(cat /tmp/schedule_driven_init_clear 2>/dev/null || echo "0")
INIT_COLLECT=$(cat /tmp/schedule_driven_init_collect 2>/dev/null || echo "0")
INIT_ABORT=$(cat /tmp/schedule_driven_init_abort 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/schedule_driven_command_execution_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/schedule_driven_command_execution_end.png 2>/dev/null || true

cat > /tmp/schedule_driven_command_execution_result.json << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "receipt_exists": $RECEIPT_EXISTS,
    "receipt_mtime": $RECEIPT_MTIME,
    "cmd_counts": {
        "initial": {
            "clear": $INIT_CLEAR,
            "collect": $INIT_COLLECT,
            "abort": $INIT_ABORT
        },
        "current": {
            "clear": $CUR_CLEAR,
            "collect": $CUR_COLLECT,
            "abort": $CUR_ABORT
        }
    }
}
EOF

echo "Script exists: $SCRIPT_EXISTS"
echo "Receipt exists: $RECEIPT_EXISTS"
echo "=== Export Complete ==="