#!/bin/bash
echo "=== Exporting Commanding Session Log Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/commanding_session_log_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/commanding_log.json"

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

# Query current command counts from API to verify the agent actually sent the commands
CURRENT_COLLECT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
CURRENT_CLEAR=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
CURRENT_ABORT=$(cosmos_api "get_cmd_cnt" '"INST","ABORT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

# Load initial counts
INITIAL_COLLECT=$(jq -r '.collect // 0' /tmp/initial_cmd_counts.json 2>/dev/null || echo "0")
INITIAL_CLEAR=$(jq -r '.clear // 0' /tmp/initial_cmd_counts.json 2>/dev/null || echo "0")
INITIAL_ABORT=$(jq -r '.abort // 0' /tmp/initial_cmd_counts.json 2>/dev/null || echo "0")

echo "COLLECT: $INITIAL_COLLECT -> $CURRENT_COLLECT"
echo "CLEAR: $INITIAL_CLEAR -> $CURRENT_CLEAR"
echo "ABORT: $INITIAL_ABORT -> $CURRENT_ABORT"

# Take final screenshot
take_screenshot /tmp/commanding_session_log_end.png

cat > /tmp/commanding_session_log_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_collect": $INITIAL_COLLECT,
    "current_collect": $CURRENT_COLLECT,
    "initial_clear": $INITIAL_CLEAR,
    "current_clear": $CURRENT_CLEAR,
    "initial_abort": $INITIAL_ABORT,
    "current_abort": $CURRENT_ABORT
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="