#!/bin/bash
echo "=== Exporting fix_steganography_tool Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_steganography_tool"
PROJECT_DIR="/home/ga/PycharmProjects/stego_toolkit"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Capture final screen
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# Run tests and capture output
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)

# Analyze code for fixes using grep patterns
LSB_FILE="$PROJECT_DIR/stego_toolkit/lsb.py"

# Check Bug 1: Masking (should use 0xFE or 254 or ~1)
BUG1_FIXED=false
if grep -qE "val\s*&\s*(0xFE|254|~1)" "$LSB_FILE"; then
    BUG1_FIXED=true
fi
# Negative check: ensure the bad mask (0x00) is gone
if grep -q "val\s*&\s*0x00" "$LSB_FILE"; then
    BUG1_FIXED=false
fi

# Check Bug 2: Base conversion (should use int(..., 2))
BUG2_FIXED=false
if grep -q "int(byte.*,\s*2)" "$LSB_FILE"; then
    BUG2_FIXED=true
fi

# Check Bug 3: Terminator (should check for '00000000')
BUG3_FIXED=false
if grep -q "00000000" "$LSB_FILE" && grep -q "break" "$LSB_FILE"; then
    BUG3_FIXED=true
fi

# Individual test pass check
TEST_FIDELITY_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_image_fidelity PASSED" && TEST_FIDELITY_PASS=true

TEST_ROUND_TRIP_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_round_trip PASSED" && TEST_ROUND_TRIP_PASS=true

TEST_TERMINATOR_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_terminator PASSED" && TEST_TERMINATOR_PASS=true

# Create JSON result
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "bug1_mask_fixed": $BUG1_FIXED,
    "bug2_base_fixed": $BUG2_FIXED,
    "bug3_terminator_fixed": $BUG3_FIXED,
    "test_fidelity_pass": $TEST_FIDELITY_PASS,
    "test_round_trip_pass": $TEST_ROUND_TRIP_PASS,
    "test_terminator_pass": $TEST_TERMINATOR_PASS
}
EOF

# Secure permissions
chmod 666 "$RESULT_FILE"

echo "Export Complete: $TESTS_PASSED passed, $TESTS_FAILED failed"