#!/bin/bash
echo "=== Exporting implement_modbus_protocol result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="implement_modbus_protocol"
PROJECT_DIR="/home/ga/PycharmProjects/modbus_rtu"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Run Tests and Capture Output
echo "Running pytest..."
cd "$PROJECT_DIR"
PYTEST_OUTPUT=$(python3 -m pytest tests/ -v 2>&1)
PYTEST_EXIT_CODE=$?

# Parse output
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -oP '(\d+) passed' | head -1 | awk '{print $1}')
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -oP '(\d+) failed' | head -1 | awk '{print $1}')
[ -z "$TESTS_PASSED" ] && TESTS_PASSED=0
[ -z "$TESTS_FAILED" ] && TESTS_FAILED=0
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

# 2. Check Test File Integrity (Anti-Gaming)
echo "Verifying test file integrity..."
md5sum "$PROJECT_DIR"/tests/*.py > /tmp/test_hashes_final.txt
TESTS_MODIFIED="false"
if ! diff -q /tmp/test_hashes_initial.txt /tmp/test_hashes_final.txt > /dev/null; then
    TESTS_MODIFIED="true"
    echo "WARNING: Test files have been modified!"
fi

# 3. Code Analysis (Static Check for Implementation Details)
# Check for CRC polynomial 0xA001 in crc.py
HAS_CRC_POLY="false"
if grep -i "0xA001" "$PROJECT_DIR/modbus/crc.py" > /dev/null; then
    HAS_CRC_POLY="true"
fi

# Check for exception handling logic (checking bit 0x80)
HAS_EXCEPTION_CHECK="false"
if grep "0x80" "$PROJECT_DIR/modbus/exceptions.py" > /dev/null; then
    HAS_EXCEPTION_CHECK="true"
fi

# 4. Construct JSON Result
cat > "$RESULT_FILE" << EOF
{
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "total_tests": $TOTAL_TESTS,
    "tests_modified": $TESTS_MODIFIED,
    "has_crc_poly": $HAS_CRC_POLY,
    "has_exception_check": $HAS_EXCEPTION_CHECK,
    "task_start_ts": $(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo 0),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"