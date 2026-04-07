#!/bin/bash
echo "=== Exporting fix_barcode_encoder Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_barcode_encoder"
PROJECT_DIR="/home/ga/PycharmProjects/barcode_encoder"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/${TASK_NAME}_final.png

# Run tests
cd "$PROJECT_DIR" || exit 1
# We expect failures initially, so don't set -e for pytest
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

# Analyze output
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

# Check for specific bug fixes via test names
UPC_CHECKSUM_FIXED="false"
CODE128_MOD_FIXED="false"
CODE128_STOP_FIXED="false"

if echo "$PYTEST_OUTPUT" | grep -q "test_upc_check_digit_standard_case PASSED"; then
    UPC_CHECKSUM_FIXED="true"
fi

if echo "$PYTEST_OUTPUT" | grep -q "test_code128_checksum_simple PASSED"; then
    CODE128_MOD_FIXED="true"
fi

if echo "$PYTEST_OUTPUT" | grep -q "test_code128_stop_pattern_termination PASSED"; then
    CODE128_STOP_FIXED="true"
fi

# Create JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "total_tests": $TOTAL_TESTS,
    "upc_checksum_fixed": $UPC_CHECKSUM_FIXED,
    "code128_mod_fixed": $CODE128_MOD_FIXED,
    "code128_stop_fixed": $CODE128_STOP_FIXED
}
EOF

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="