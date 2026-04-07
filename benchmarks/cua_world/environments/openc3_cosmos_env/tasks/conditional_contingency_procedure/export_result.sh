#!/bin/bash
echo "=== Exporting Conditional Contingency Procedure Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/conditional_contingency_procedure_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/conditional_pass_report.json"

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

# Query current command counts
INITIAL_COLLECT=$(cat /tmp/conditional_contingency_initial_collect 2>/dev/null || echo "0")
INITIAL_ABORT=$(cat /tmp/conditional_contingency_initial_abort 2>/dev/null || echo "0")

CURRENT_COLLECT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
CURRENT_ABORT=$(cosmos_api "get_cmd_cnt" '"INST","ABORT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

echo "COLLECT count: $INITIAL_COLLECT -> $CURRENT_COLLECT"
echo "ABORT count: $INITIAL_ABORT -> $CURRENT_ABORT"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/conditional_contingency_procedure_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/conditional_contingency_procedure_end.png 2>/dev/null || true

cat > /tmp/conditional_contingency_procedure_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_collect_count": $INITIAL_COLLECT,
    "current_collect_count": $CURRENT_COLLECT,
    "initial_abort_count": $INITIAL_ABORT,
    "current_abort_count": $CURRENT_ABORT
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="