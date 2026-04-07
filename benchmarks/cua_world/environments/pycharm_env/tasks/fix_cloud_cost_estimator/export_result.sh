#!/bin/bash
echo "=== Exporting fix_cloud_cost_estimator Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/cloud_cost_estimator"
RESULT_FILE="/tmp/fix_cloud_cost_estimator_result.json"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run tests and capture output
echo "Running tests..."
cd "$PROJECT_DIR"
PYTEST_OUTPUT=$(python3 -m pytest tests/ -v 2>&1)
PYTEST_EXIT_CODE=$?

echo "Pytest exit code: $PYTEST_EXIT_CODE"

# Parse Test Results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)

# Specific Test Checks
TEST_STORAGE_PASS=$(echo "$PYTEST_OUTPUT" | grep -q "test_storage_gb_to_gib_conversion PASSED" && echo "true" || echo "false")
TEST_TRANSFER_PASS=$(echo "$PYTEST_OUTPUT" | grep -q "test_tiered_pricing_cumulative PASSED" && echo "true" || echo "false")
TEST_REGION_PASS=$(echo "$PYTEST_OUTPUT" | grep -q "test_region_lookup_with_az PASSED" && echo "true" || echo "false")

# Static Analysis Checks (Backup verification)
ESTIMATOR_FILE="$PROJECT_DIR/src/estimator.py"
FILE_CONTENT=$(cat "$ESTIMATOR_FILE")

# Check 1: Unit conversion (Look for conversion factor)
# 10**9 / 2**30 approx 0.931 or constants 1000/1024^3
UNIT_FIX_DETECTED="false"
if grep -q "10\*\*9" "$ESTIMATOR_FILE" && grep -q "2\*\*30" "$ESTIMATOR_FILE"; then
    UNIT_FIX_DETECTED="true"
elif grep -q "1000" "$ESTIMATOR_FILE" && grep -q "1024" "$ESTIMATOR_FILE"; then
    UNIT_FIX_DETECTED="true"
elif grep -q "0.931322" "$ESTIMATOR_FILE"; then
    UNIT_FIX_DETECTED="true"
fi

# Check 2: Tiered pricing (Look for loop accumulating cost)
# Should assume iterating over tiers and adding to cost, or subtracting limit
TIER_FIX_DETECTED="false"
if echo "$FILE_CONTENT" | grep -q "+="; then
    # Very naive check, but cumulative calc usually involves addition inside loop
    TIER_FIX_DETECTED="true"
fi

# Check 3: Region stripping (Look for split, slice, or regex)
REGION_FIX_DETECTED="false"
if grep -q "[:-1]" "$ESTIMATOR_FILE" || grep -q "re\.sub" "$ESTIMATOR_FILE"; then
    REGION_FIX_DETECTED="true"
fi

# Construct JSON
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "test_storage_pass": $TEST_STORAGE_PASS,
    "test_transfer_pass": $TEST_TRANSFER_PASS,
    "test_region_pass": $TEST_REGION_PASS,
    "unit_fix_detected": $UNIT_FIX_DETECTED,
    "tier_fix_detected": $TIER_FIX_DETECTED,
    "region_fix_detected": $REGION_FIX_DETECTED,
    "app_running": $(pgrep -f pycharm > /dev/null && echo "true" || echo "false")
}
EOF

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="