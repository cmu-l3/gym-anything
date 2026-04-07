#!/bin/bash
echo "=== Exporting Translation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/nl_translation_start_ts 2>/dev/null || echo "0")
SCRIPT_FILE="/home/ga/Desktop/observation_sequence.py"

FILE_EXISTS="false"
FILE_IS_NEW="false"
SYNTAX_OK="false"
EXIT_CODE=-1
EXEC_TIME=0
COLLECT_DELTA=0
CLEAR_DELTA=0

if [ -f "$SCRIPT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi

    # Check syntax before attempting execution
    if python3 -m py_compile "$SCRIPT_FILE" > /dev/null 2>&1; then
        SYNTAX_OK="true"

        # Get initial command counts
        INIT_COLLECT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
        INIT_CLEAR=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

        # Execute the script in a bounded sandbox to verify behavior actively
        echo "Executing agent script for dynamic analysis..."
        START_EXEC=$(date +%s.%N)
        
        # We run the script using 'su - ga' with a 15 second timeout to prevent hanging.
        timeout 15s su - ga -c "python3 $SCRIPT_FILE" > /tmp/agent_script_execution.log 2>&1
        EXIT_CODE=$?
        
        END_EXEC=$(date +%s.%N)
        # Use awk for floating point math compatibility
        EXEC_TIME=$(awk "BEGIN {print $END_EXEC - $START_EXEC}")

        # Get final command counts
        FINAL_COLLECT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
        FINAL_CLEAR=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

        COLLECT_DELTA=$((FINAL_COLLECT - INIT_COLLECT))
        CLEAR_DELTA=$((FINAL_CLEAR - INIT_CLEAR))
        
        echo "Execution took ${EXEC_TIME}s, Exit Code: $EXIT_CODE"
        echo "COLLECT delta: $COLLECT_DELTA, CLEAR delta: $CLEAR_DELTA"
    else
        echo "Syntax check failed, skipping active execution."
    fi
fi

# Write results
cat > /tmp/nl_translation_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "syntax_ok": $SYNTAX_OK,
    "exit_code": $EXIT_CODE,
    "exec_time_seconds": $EXEC_TIME,
    "collect_delta": $COLLECT_DELTA,
    "clear_delta": $CLEAR_DELTA
}
EOF

# Take final screenshot
DISPLAY=:1 import -window root /tmp/nl_translation_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/nl_translation_end.png 2>/dev/null || true

echo "=== Export Complete ==="