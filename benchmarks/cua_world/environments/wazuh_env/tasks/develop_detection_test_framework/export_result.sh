#!/bin/bash
echo "=== Exporting develop_detection_test_framework results ==="

SCRIPT_PATH="/home/ga/validate_detections.py"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if script exists
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH" | base64 -w 0)
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi

    # 2. Execute the script and capture output
    echo "Executing agent script..."
    # We run as 'ga' user since that's who the agent is
    # Using python3 unbuffered output
    if su - ga -c "python3 -u $SCRIPT_PATH" > /tmp/script_stdout.txt 2> /tmp/script_stderr.txt; then
        EXECUTION_SUCCESS="true"
        EXIT_CODE=0
    else
        EXECUTION_SUCCESS="false"
        EXIT_CODE=$?
    fi
    
    SCRIPT_STDOUT=$(cat /tmp/script_stdout.txt | base64 -w 0)
    SCRIPT_STDERR=$(cat /tmp/script_stderr.txt | base64 -w 0)

else
    SCRIPT_EXISTS="false"
    SCRIPT_CONTENT=""
    CREATED_DURING_TASK="false"
    EXECUTION_SUCCESS="false"
    EXIT_CODE=-1
    SCRIPT_STDOUT=""
    SCRIPT_STDERR=""
fi

# Take final screenshot
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "script_content_b64": "$SCRIPT_CONTENT",
    "execution_success": $EXECUTION_SUCCESS,
    "exit_code": $EXIT_CODE,
    "stdout_b64": "$SCRIPT_STDOUT",
    "stderr_b64": "$SCRIPT_STDERR",
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"