#!/bin/bash
echo "=== Exporting PEBL fMRI Adaptation result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_mtime.txt 2>/dev/null || echo "0")
SCRIPT_PATH="/home/ga/pebl/experiments/fmri_gng/gng_task.pbl"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"
SYNTAX_ERROR="false"
PARSER_OUTPUT=""

if [ -f "$SCRIPT_PATH" ]; then
    FILE_EXISTS="true"
    CURRENT_MTIME=$(stat -c %Y "$SCRIPT_PATH")
    FILE_SIZE=$(stat -c %s "$SCRIPT_PATH")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi

    # Run a quick syntax check on the modified script
    # Timeout after 2 seconds (if it parses, it runs the dummy loop very fast)
    echo "Running PEBL syntax check..."
    timeout 2 su - ga -c "DISPLAY=:1 /usr/local/bin/run-pebl '$SCRIPT_PATH'" > /tmp/pebl_syntax.log 2>&1
    EXIT_CODE=$?
    
    # Exit code 124 is timeout (which means it parsed and was running!), 
    # 0 is clean exit. Other codes (or "Syntax Error" in output) indicate broken code.
    PARSER_OUTPUT=$(cat /tmp/pebl_syntax.log | tr '\n' ' ' | sed 's/"/'\''/g')
    if grep -qi "Syntax Error\|Fatal Error\|Parse error" /tmp/pebl_syntax.log; then
        SYNTAX_ERROR="true"
        echo "Syntax error detected in modified script."
    fi
fi

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "syntax_error": $SYNTAX_ERROR,
    "parser_output": "$PARSER_OUTPUT"
}
EOF

# Move and set permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="