#!/bin/bash
echo "=== Exporting External API Macro Development Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/external_api_macro_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/deploy_macro.py"

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
CURRENT_COLLECT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
CURRENT_CLEAR=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
CURRENT_ABORT=$(cosmos_api "get_cmd_cnt" '"INST","ABORT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

# Load initial counts safely
if [ -f /tmp/external_api_macro_initial_counts.json ]; then
    INITIAL_COLLECT=$(jq -r '.collect' /tmp/external_api_macro_initial_counts.json)
    INITIAL_CLEAR=$(jq -r '.clear' /tmp/external_api_macro_initial_counts.json)
    INITIAL_ABORT=$(jq -r '.abort' /tmp/external_api_macro_initial_counts.json)
else
    INITIAL_COLLECT=0
    INITIAL_CLEAR=0
    INITIAL_ABORT=0
fi

# Take final screenshot
DISPLAY=:1 import -window root /tmp/external_api_macro_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/external_api_macro_end.png 2>/dev/null || true

cat > /tmp/external_api_macro_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_counts": {
        "collect": $INITIAL_COLLECT,
        "clear": $INITIAL_CLEAR,
        "abort": $INITIAL_ABORT
    },
    "current_counts": {
        "collect": $CURRENT_COLLECT,
        "clear": $CURRENT_CLEAR,
        "abort": $CURRENT_ABORT
    }
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "Initial counts: COLLECT=$INITIAL_COLLECT, CLEAR=$INITIAL_CLEAR, ABORT=$INITIAL_ABORT"
echo "Current counts: COLLECT=$CURRENT_COLLECT, CLEAR=$CURRENT_CLEAR, ABORT=$CURRENT_ABORT"
echo "=== Export Complete ==="