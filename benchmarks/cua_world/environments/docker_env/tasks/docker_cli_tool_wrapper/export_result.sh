#!/bin/bash
# Export script for docker_cli_tool_wrapper
# This script ACTUALLY RUNS the agent's wrapper to verify functionality

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_end_screenshot.png
fi

WRAPPER_PATH="/home/ga/projects/tools/db-migrate"
TEST_DIR="/home/ga/projects/myapp"
REPORT_FILE="$TEST_DIR/report.log"

# Initialize results
EXISTS=0
EXECUTABLE=0
RUNS_SUCCESSFULLY=0
PERMISSIONS_CORRECT=0
NET_CONNECTED=0
ARGS_PASSED=0
ENV_PASSED=0
CLEANUP_FLAG=0
USER_FLAG=0
NET_FLAG=0
VOL_FLAG=0
ARG_ARRAY_USED=0

# 1. Static Analysis
if [ -f "$WRAPPER_PATH" ]; then
    EXISTS=1
    [ -x "$WRAPPER_PATH" ] && EXECUTABLE=1
    
    # Check for critical flags in the script content
    grep -q "\--rm" "$WRAPPER_PATH" && CLEANUP_FLAG=1
    grep -E "\--user|\-u" "$WRAPPER_PATH" && USER_FLAG=1
    grep -E "\--network|\--net" "$WRAPPER_PATH" && NET_FLAG=1
    grep -E "\-v|\--volume|\--mount" "$WRAPPER_PATH" && VOL_FLAG=1
    grep -q '"$@"' "$WRAPPER_PATH" && ARG_ARRAY_USED=1
fi

# 2. Functional Test
if [ "$EXECUTABLE" = "1" ]; then
    echo "Running functional test..."
    
    # Clean up any previous test artifacts
    rm -f "$REPORT_FILE"
    
    # Run the wrapper as user 'ga'
    # We pass a specific test argument and set the env var
    OUTPUT=$(su - ga -c "export DB_HOST=acme-db; cd $TEST_DIR; $WRAPPER_PATH verify-status --verbose" 2>&1)
    EXIT_CODE=$?
    
    echo "Wrapper Output:"
    echo "$OUTPUT"
    
    if [ $EXIT_CODE -eq 0 ]; then
        RUNS_SUCCESSFULLY=1
        
        # Check if arguments were passed (look for them in the tool's output)
        if echo "$OUTPUT" | grep -q "'verify-status', '--verbose'"; then
            ARGS_PASSED=1
        fi
        
        # Check connectivity (look for success message from tool)
        if echo "$OUTPUT" | grep -q "Successfully resolved acme-db"; then
            NET_CONNECTED=1
        fi
        
        # Check env var passing
        if echo "$OUTPUT" | grep -q "DB_HOST is set to: acme-db"; then
            ENV_PASSED=1
        fi
        
        # Check permissions of the generated file
        if [ -f "$REPORT_FILE" ]; then
            FILE_UID=$(stat -c '%u' "$REPORT_FILE")
            GA_UID=$(id -u ga)
            if [ "$FILE_UID" = "$GA_UID" ]; then
                PERMISSIONS_CORRECT=1
            else
                echo "Permission Check Failed: File owned by $FILE_UID, expected $GA_UID"
            fi
        else
            echo "Artifact check failed: report.log not created"
        fi
    fi
fi

# 3. Create JSON Result
cat > /tmp/wrapper_result.json <<EOF
{
    "script_exists": $EXISTS,
    "script_executable": $EXECUTABLE,
    "runs_successfully": $RUNS_SUCCESSFULLY,
    "permissions_correct": $PERMISSIONS_CORRECT,
    "net_connected": $NET_CONNECTED,
    "args_passed": $ARGS_PASSED,
    "env_passed": $ENV_PASSED,
    "static_cleanup": $CLEANUP_FLAG,
    "static_user": $USER_FLAG,
    "static_net": $NET_FLAG,
    "static_vol": $VOL_FLAG,
    "static_arg_array": $ARG_ARRAY_USED,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/wrapper_result.json
echo "=== Export Complete ==="