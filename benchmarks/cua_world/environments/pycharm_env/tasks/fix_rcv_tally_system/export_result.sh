#!/bin/bash
echo "=== Exporting fix_rcv_tally_system Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_rcv_tally_system"
PROJECT_DIR="/home/ga/PycharmProjects/rcv_tally"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Run Tests
# We expect all tests to pass now.
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# 3. Check specific code fixes (Static Analysis via Grep)

# Bug 1: Loader normalization (title or upper case)
LOADER_FILE="$PROJECT_DIR/tally/loader.py"
LOADER_FIXED=false
if grep -qE "candidate\.strip\(\)\.(title|upper|lower|capitalize)\(\)" "$LOADER_FILE"; then
    LOADER_FIXED=true
fi
# Alternatively, if they implemented custom logic, rely on the test `test_normalization` passing.

# Bug 2: Transfer logic (looping or recursion in _get_top_choice)
ENGINE_FILE="$PROJECT_DIR/tally/engine.py"
TRANSFER_FIXED=false
# Look for a loop (while/for) or recursion in _get_top_choice
if grep -q "for .* in ballot" "$ENGINE_FILE" || grep -q "while" "$ENGINE_FILE"; then
    # Must also check against eliminated
    if grep -q "if .* not in .*eliminated" "$ENGINE_FILE"; then
        TRANSFER_FIXED=true
    fi
fi
# Weak check, rely on `test_transfer_logic_skips_eliminated` passing.

# Bug 3: Threshold (active ballots)
THRESHOLD_FIXED=false
# Check if threshold calc involves active count (e.g. active_ballots_count / 2)
# Original buggy: total_initial_ballots / 2
if grep -q "active_ballots_count / 2" "$ENGINE_FILE" || grep -q "active_ballots_count // 2" "$ENGINE_FILE"; then
    THRESHOLD_FIXED=true
fi

# 4. Run Main Script (End-to-End Verification)
MAIN_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 main.py 2>&1")
# We assume the correct winner for the provided CSV is "Alice" after fixes.
# (Before fixes, case sensitivity splits Alice's vote, and Dave's transfer might fail)
CORRECT_WINNER_FOUND=false
if echo "$MAIN_OUTPUT" | grep -q "The winner is: Alice"; then
    CORRECT_WINNER_FOUND=true
fi

# Create JSON Result
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "loader_fixed_static": $LOADER_FIXED,
    "transfer_fixed_static": $TRANSFER_FIXED,
    "threshold_fixed_static": $THRESHOLD_FIXED,
    "correct_winner_found": $CORRECT_WINNER_FOUND,
    "main_output_tail": "$(echo "$MAIN_OUTPUT" | tail -n 5 | tr '\n' ' ')"
}
EOF

echo "Export complete. Winner found: $CORRECT_WINNER_FOUND. Tests passed: $TESTS_PASSED"