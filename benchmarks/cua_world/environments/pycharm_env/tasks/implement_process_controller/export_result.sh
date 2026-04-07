#!/bin/bash
set -e
echo "=== Exporting implement_process_controller Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="implement_process_controller"
PROJECT_DIR="/home/ga/PycharmProjects/process_controller"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
take_screenshot /tmp/${TASK_NAME}_final_screenshot.png

# Run pytest and capture detailed output
# Using --tb=short to be concise but informative
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

# Analyze test results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

# Categorize passed tests
TRANSITION_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_transitions.py" | grep -c " PASSED" || true)
GUARDS_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_guards.py" | grep -c " PASSED" || true)
ACTIONS_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_actions.py" | grep -c " PASSED" || true)

# Verify test file integrity (anti-gaming)
TEST_INTEGRITY=true
if [ -f /tmp/initial_test_hashes.txt ]; then
    CURRENT_HASHES=$(md5sum "$PROJECT_DIR/tests/"*.py)
    # Compare hashes ignoring whitespace
    if ! diff -w <(cat /tmp/initial_test_hashes.txt) <(echo "$CURRENT_HASHES") > /dev/null; then
        TEST_INTEGRITY=false
        echo "WARNING: Test files have been modified!"
    fi
fi

# Determine source file status (basic check: are they empty?)
MACHINE_SIZE=$(stat -c%s "$PROJECT_DIR/controller/machine.py" 2>/dev/null || echo "0")
GUARDS_SIZE=$(stat -c%s "$PROJECT_DIR/controller/guards.py" 2>/dev/null || echo "0")
ACTIONS_SIZE=$(stat -c%s "$PROJECT_DIR/controller/actions.py" 2>/dev/null || echo "0")

SOURCE_FILES_EXIST=false
if [ "$MACHINE_SIZE" -gt 100 ] && [ "$GUARDS_SIZE" -gt 100 ] && [ "$ACTIONS_SIZE" -gt 100 ]; then
    SOURCE_FILES_EXIST=true
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_name": "$TASK_NAME",
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_total": $TESTS_TOTAL,
    "transition_tests_passed": $TRANSITION_PASS,
    "guard_tests_passed": $GUARDS_PASS,
    "action_tests_passed": $ACTIONS_PASS,
    "test_integrity": $TEST_INTEGRITY,
    "source_files_exist": $SOURCE_FILES_EXIST,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with proper permissions
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="