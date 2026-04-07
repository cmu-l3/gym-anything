#!/bin/bash
echo "=== Exporting fix_deduplication_utility Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_deduplication_utility"
PROJECT_DIR="/home/ga/PycharmProjects/smart_dedup"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/dedup_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run tests
echo "Running tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

echo "Test Output:"
echo "$PYTEST_OUTPUT"

# Parse Test Results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)

# Check specific tests
TEST_INTEGRITY_PASS=$(echo "$PYTEST_OUTPUT" | grep -q "test_partial_hash_collision PASSED" && echo "true" || echo "false")
TEST_CRASH_PASS=$(echo "$PYTEST_OUTPUT" | grep -q "test_hardlink_crash PASSED" && echo "true" || echo "false")
TEST_SMALL_PASS=$(echo "$PYTEST_OUTPUT" | grep -q "test_small_files_ignored PASSED" && echo "true" || echo "false")

# Static Analysis / Code Inspection
SRC_FILE="$PROJECT_DIR/smart_dedup.py"

# Bug 1 Fix Check: Look for loop reading or reading all bytes
# Buggy code had: chunk = f.read(2048) ... if chunk: h.update(chunk)
# Fixed code should have a loop "while chunk:" or "read()" (all) or "for chunk in iter..."
FIX_HASHING="false"
if grep -q "while chunk" "$SRC_FILE" || grep -q "iter(" "$SRC_FILE" || grep -q "read()" "$SRC_FILE"; then
    FIX_HASHING="true"
fi
# Negative check: ensure the specific buggy 2048 single read pattern is gone or modified
# The buggy code: `chunk = f.read(2048)` followed immediately by update/return without loop
# This is hard to grep perfectly, relying on test result is better, but this helps.

# Bug 2 Fix Check: Look for os.remove or unlink before link
FIX_LINKING="false"
if grep -q "os.remove" "$SRC_FILE" || grep -q "os.unlink" "$SRC_FILE" || grep -q "pathlib.*unlink" "$SRC_FILE"; then
    FIX_LINKING="true"
fi

# Bug 3 Fix Check: Look for size < 1024 check
FIX_FILTER="false"
if ! grep -q "size < 1024" "$SRC_FILE"; then
    FIX_FILTER="true"
fi

# Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "timestamp": "$(date -Iseconds)",
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "test_integrity_pass": $TEST_INTEGRITY_PASS,
    "test_crash_pass": $TEST_CRASH_PASS,
    "test_small_pass": $TEST_SMALL_PASS,
    "static_hash_fix": $FIX_HASHING,
    "static_link_fix": $FIX_LINKING,
    "static_filter_fix": $FIX_FILTER
}
EOF

# Safe copy to tmp for extraction
cp "$RESULT_FILE" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="