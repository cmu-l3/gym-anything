#!/bin/bash
echo "=== Exporting debug_multithreaded_processor result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="debug_multithreaded_processor"
PROJECT_DIR="/home/ga/PycharmProjects/transaction_engine"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"

# 1. Take final screenshot
take_screenshot /tmp/${TASK_NAME}_final.png

# 2. Run Tests
# We use a timeout to ensure the deadlock test doesn't hang the export script indefinitely
# 'timeout 30s' kills the command if it hangs
echo "Running tests..."
cd "$PROJECT_DIR"

# Run balance test (Race Condition check)
PYTEST_BALANCE=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/test_balances.py -v 2>&1")
BALANCE_RET=$?

# Run stress test (Deadlock check)
# Using 'timeout' command to enforce limit if agent didn't fix deadlock
PYTEST_STRESS=$(su - ga -c "cd '$PROJECT_DIR' && timeout 20s python3 -m pytest tests/test_stress.py -v 2>&1")
STRESS_RET=$?
# 124 is the return code for timeout command if it kills the process
if [ $STRESS_RET -eq 124 ]; then
    STRESS_MSG="TIMEOUT_DETECTED"
else
    STRESS_MSG="COMPLETED"
fi

# 3. Static Analysis
# Check if Lock is used in Account._update_balance
ACCOUNT_FILE="app/account.py"
LOCK_USED_ACCOUNT=false
if grep -q "with self._lock:" "$ACCOUNT_FILE" 2>/dev/null || grep -q "self._lock.acquire" "$ACCOUNT_FILE" 2>/dev/null; then
    # Ensure it's inside _update_balance or deposit/withdraw
    LOCK_USED_ACCOUNT=true
fi

# Check if sorting/ordering is used in Transfer
TRANSFER_FILE="app/transfer.py"
LOCK_ORDERING_USED=false
if grep -q "sorted(" "$TRANSFER_FILE" 2>/dev/null || \
   grep -q "id(" "$TRANSFER_FILE" 2>/dev/null || \
   grep -q "<" "$TRANSFER_FILE" 2>/dev/null; then
    LOCK_ORDERING_USED=true
fi

# 4. Construct JSON
cat > "$RESULT_FILE" << EOF
{
    "balance_test_passed": $([ $BALANCE_RET -eq 0 ] && echo "true" || echo "false"),
    "stress_test_passed": $([ $STRESS_RET -eq 0 ] && echo "true" || echo "false"),
    "stress_test_status": "$STRESS_MSG",
    "lock_used_in_account": $LOCK_USED_ACCOUNT,
    "lock_ordering_detected": $LOCK_ORDERING_USED,
    "timestamp": $(date +%s)
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="