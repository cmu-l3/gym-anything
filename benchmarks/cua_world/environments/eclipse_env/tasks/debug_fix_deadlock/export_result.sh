#!/bin/bash
echo "=== Exporting debug_fix_deadlock result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/FinancialSystem"
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_end.png

# --- Data Collection ---

# 1. Check for analysis file
ANALYSIS_FILE="$PROJECT_DIR/analysis.txt"
ANALYSIS_EXISTS="false"
ANALYSIS_CONTENT=""
if [ -f "$ANALYSIS_FILE" ]; then
    ANALYSIS_EXISTS="true"
    ANALYSIS_CONTENT=$(cat "$ANALYSIS_FILE")
fi

# 2. Collect Source Code
TRANSFER_SERVICE="$PROJECT_DIR/src/main/java/com/financial/core/TransferService.java"
CODE_CONTENT=""
if [ -f "$TRANSFER_SERVICE" ]; then
    CODE_CONTENT=$(cat "$TRANSFER_SERVICE")
fi

# 3. VERIFY FIX EXECUTION (Run the simulation in the container)
# We compile and run the code here because we can't execute Java inside verifier.py (host side)
# We use 'timeout' to detect if it still deadlocks.

echo "Compiling project..."
mkdir -p "$PROJECT_DIR/bin_verify"
javac -d "$PROJECT_DIR/bin_verify" \
    "$PROJECT_DIR/src/main/java/com/financial/core/Account.java" \
    "$PROJECT_DIR/src/main/java/com/financial/core/TransferService.java" \
    "$PROJECT_DIR/src/main/java/com/financial/simulation/DeadlockDemo.java" 2> /tmp/compile_error.log

COMPILE_STATUS=$?
EXECUTION_STATUS="not_run"
EXECUTION_OUTPUT=""

if [ $COMPILE_STATUS -eq 0 ]; then
    echo "Running simulation with 10s timeout..."
    # Run with timeout. If it hangs (deadlock), timeout kills it and returns 124
    EXECUTION_OUTPUT=$(timeout 10s java -cp "$PROJECT_DIR/bin_verify" com.financial.simulation.DeadlockDemo 2>&1)
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        EXECUTION_STATUS="success"
    elif [ $EXIT_CODE -eq 124 ]; then
        EXECUTION_STATUS="timeout_deadlock"
    else
        EXECUTION_STATUS="error_exit_$EXIT_CODE"
    fi
else
    EXECUTION_STATUS="compile_failed"
    EXECUTION_OUTPUT=$(cat /tmp/compile_error.log)
fi

# Escape content for JSON
ESC_ANALYSIS=$(echo "$ANALYSIS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ESC_CODE=$(echo "$CODE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ESC_OUTPUT=$(echo "$EXECUTION_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create Result JSON
cat > "$RESULT_JSON" << EOF
{
    "analysis_exists": $ANALYSIS_EXISTS,
    "analysis_content": $ESC_ANALYSIS,
    "code_content": $ESC_CODE,
    "execution_status": "$EXECUTION_STATUS",
    "execution_output": $ESC_OUTPUT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions so host can read it via copy_from_env
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
echo "Execution Status: $EXECUTION_STATUS"