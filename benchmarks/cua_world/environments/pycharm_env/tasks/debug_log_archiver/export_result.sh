#!/bin/bash
echo "=== Exporting debug_log_archiver result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="debug_log_archiver"
PROJECT_DIR="/home/ga/PycharmProjects/log_archiver"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run tests
echo "Running test suite..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

# Analyze Code for Specific Fixes (Static Analysis)

# 1. Check Data Safety Fix (Bug 1)
# We check if os.remove is still inside a finally block OR if it's moved to a safe location.
# Since parsing python with regex is hard, we rely heavily on the 'test_archive_failure_preserves_source' passing.
# But we can also look for the pattern: "finally: ... os.remove"
CORE_PY="$PROJECT_DIR/archiver/core.py"
UNSAFE_DELETE_PATTERN_DETECTED="false"
# Simple heuristic: check if os.remove is indented under finally
# This is a bit brittle, so the test suite result is the primary signal.

# 2. Check Regex Fix (Bug 2)
# Look for regex that allows dashes in date
REGEX_FIXED="false"
if grep -q "r\".*\.\\d{8}\"" "$CORE_PY" 2>/dev/null; then
    REGEX_FIXED="false" # Still the old strict regex
else
    # Check if a more permissive regex is present, e.g., allowing dashes
    if grep -qE "r\".*\\.(\\d{8}|\\d{4}-\\d{2}-\\d{2})\"|r\".*\\.[0-9-]+\"" "$CORE_PY"; then
        REGEX_FIXED="true"
    fi
fi

# 3. Check Disk Space Implementation (Bug 3)
VALIDATORS_PY="$PROJECT_DIR/archiver/validators.py"
DISK_CHECK_IMPLEMENTED="false"
if grep -q "shutil.disk_usage" "$VALIDATORS_PY"; then
    DISK_CHECK_IMPLEMENTED="true"
fi

# Extract specific test results
TEST_SAFETY_PASS="false"
echo "$PYTEST_OUTPUT" | grep -q "test_archive_failure_preserves_source PASSED" && TEST_SAFETY_PASS="true"

TEST_REGEX_PASS="false"
echo "$PYTEST_OUTPUT" | grep -q "test_discover_iso_dates PASSED" && TEST_REGEX_PASS="true"

TEST_DISK_PASS="false"
echo "$PYTEST_OUTPUT" | grep -q "test_check_disk_space_insufficient PASSED" && TEST_DISK_PASS="true"

# Construct Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_total": $TESTS_TOTAL,
    "regex_fixed_heuristic": $REGEX_FIXED,
    "disk_check_implemented": $DISK_CHECK_IMPLEMENTED,
    "test_safety_pass": $TEST_SAFETY_PASS,
    "test_regex_pass": $TEST_REGEX_PASS,
    "test_disk_pass": $TEST_DISK_PASS,
    "screenshot_path": "/tmp/task_end.png"
}
EOF

# Save result safely
chmod 666 "$RESULT_FILE"

echo "=== Export complete ==="
cat "$RESULT_FILE"