#!/bin/bash
echo "=== Exporting fix_cloud_backup_rotator Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/cloud_rotator"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run tests with a timeout to prevent infinite loop (Bug 1) from hanging the verification
# Use 'timeout' command. 30s should be plenty for 3 tests.
echo "Running tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && timeout 30s python3 -m pytest tests/test_policy.py -v 2>&1")
PYTEST_EXIT_CODE=$?

echo "Pytest exit code: $PYTEST_EXIT_CODE"

# Parse results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)

# Specific test results
RETENTION_PASS="false"
GLACIER_PASS="false"
PAGINATION_PASS="false"

echo "$PYTEST_OUTPUT" | grep -q "test_retention_keeps_newest PASSED" && RETENTION_PASS="true"
echo "$PYTEST_OUTPUT" | grep -q "test_skips_glacier PASSED" && GLACIER_PASS="true"
echo "$PYTEST_OUTPUT" | grep -q "test_large_bucket_pagination PASSED" && PAGINATION_PASS="true"

# Static analysis checks (Backup verification)
# Check for 'GLACIER' in the policy file loop
POLICY_FILE="$PROJECT_DIR/rotator/policy.py"
GLACIER_CHECK_PRESENT="false"
if grep -q "GLACIER" "$POLICY_FILE"; then
    GLACIER_CHECK_PRESENT="true"
fi

# Check for correct slicing logic
# Bad: [:retention_count]
# Good: [retention_count:]
SLICING_CHECK="false"
if grep -q "\[retention_count:\]" "$POLICY_FILE"; then
    SLICING_CHECK="true"
fi

# Create JSON result
cat > "$RESULT_FILE" << EOF
{
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "retention_passed": $RETENTION_PASS,
    "glacier_passed": $GLACIER_PASS,
    "pagination_passed": $PAGINATION_PASS,
    "glacier_check_in_code": $GLACIER_CHECK_PRESENT,
    "slicing_check_in_code": $SLICING_CHECK,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"

echo "=== Export complete ==="