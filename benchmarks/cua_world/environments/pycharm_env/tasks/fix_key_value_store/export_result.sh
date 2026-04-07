#!/bin/bash
echo "=== Exporting fix_key_value_store Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_key_value_store"
PROJECT_DIR="/home/ga/PycharmProjects/pylsm_engine"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
START_TS=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# Run tests
cd "$PROJECT_DIR"
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

# --- Static Analysis for Bug Fixes ---

# Bug 1: Binary Search (check for logic change in loop)
# Look for 'high = mid - 1' which fixes the off-by-one
BUG1_FIXED="false"
if grep -q "high = mid - 1" "$PROJECT_DIR/pylsm/sstable.py"; then
    BUG1_FIXED="true"
fi

# Bug 2: Merge Priority (check logic in compaction.py)
# The bug was 'yield (k2, v2)'. The fix should yield '(k1, v1)'.
BUG2_FIXED="false"
if grep -q "yield (k1, v1)" "$PROJECT_DIR/pylsm/compaction.py"; then
    # Ensure it's inside the equality check block (simple heuristic)
    if ! grep -q "yield (k2, v2)" "$PROJECT_DIR/pylsm/compaction.py"; then
        # This is a loose check, relied more on test passing
        BUG2_FIXED="true"
    fi
fi
# Better check: test_merge_priority pass status
if echo "$PYTEST_OUTPUT" | grep -q "test_merge_priority PASSED"; then
    BUG2_FIXED="true"
fi
if echo "$PYTEST_OUTPUT" | grep -q "test_binary_search_boundary PASSED"; then
    BUG1_FIXED="true"
fi

# Bug 3: Tombstone (check for explicit return None)
BUG3_FIXED="false"
# Look for "return None" inside the TOMBSTONE check
if grep -zqo "val == TOMBSTONE:.*return None" "$PROJECT_DIR/pylsm/lsm.py"; then
     BUG3_FIXED="true"
fi
# Or check test status
if echo "$PYTEST_OUTPUT" | grep -q "test_tombstone_masking PASSED"; then
    BUG3_FIXED="true"
fi


# Generate JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "timestamp": "$(date -Iseconds)",
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "total_tests": $TOTAL_TESTS,
    "bug1_binary_search_fixed": $BUG1_FIXED,
    "bug2_merge_priority_fixed": $BUG2_FIXED,
    "bug3_tombstone_fixed": $BUG3_FIXED
}
EOF

echo "Results exported to $RESULT_FILE"
cat "$RESULT_FILE"