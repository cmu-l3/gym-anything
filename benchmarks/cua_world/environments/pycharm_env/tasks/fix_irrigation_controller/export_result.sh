#!/bin/bash
echo "=== Exporting fix_irrigation_controller Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_irrigation_controller"
PROJECT_DIR="/home/ga/PycharmProjects/smart_irrigate"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# Run tests
echo "Running tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

echo "Tests passed: $TESTS_PASSED / $TESTS_TOTAL"

# --- Static Analysis of Fixes ---

# Bug 1: ETo Formula
# Check for + 17.8
BUG1_FIXED=false
if grep -q "\+\s*17\.8" "$PROJECT_DIR/control/evapotranspiration.py"; then
    BUG1_FIXED=true
fi
# Also verify test passed
if echo "$PYTEST_OUTPUT" | grep -q "test_hargreaves_basic PASSED"; then
    TEST_ETO_PASS=true
else
    TEST_ETO_PASS=false
fi

# Bug 2: Scheduler Logic
# Check for > rain_threshold (or >=)
BUG2_FIXED=false
SCHEDULER_CONTENT=$(cat "$PROJECT_DIR/control/scheduler.py")
if echo "$SCHEDULER_CONTENT" | grep -q "rain_probability\s*>\s*rain_threshold"; then
    BUG2_FIXED=true
elif echo "$SCHEDULER_CONTENT" | grep -q "rain_probability\s*>=\s*rain_threshold"; then
    BUG2_FIXED=true
fi
# Verify test passed
if echo "$PYTEST_OUTPUT" | grep -q "test_skip_watering_if_rain_likely PASSED"; then
    TEST_SCHEDULER_PASS=true
else
    TEST_SCHEDULER_PASS=false
fi

# Bug 3: Sensor None handling
# Check for filter or list comprehension checking None
BUG3_FIXED=false
SENSORS_CONTENT=$(cat "$PROJECT_DIR/control/sensors.py")
if echo "$SENSORS_CONTENT" | grep -q "is not None"; then
    BUG3_FIXED=true
fi
# Verify test passed
if echo "$PYTEST_OUTPUT" | grep -q "test_average_with_dropped_packets PASSED"; then
    TEST_SENSORS_PASS=true
else
    TEST_SENSORS_PASS=false
fi

# Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_total": $TESTS_TOTAL,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_fixed_static": $BUG1_FIXED,
    "test_eto_pass": $TEST_ETO_PASS,
    "bug2_fixed_static": $BUG2_FIXED,
    "test_scheduler_pass": $TEST_SCHEDULER_PASS,
    "bug3_fixed_static": $BUG3_FIXED,
    "test_sensors_pass": $TEST_SENSORS_PASS
}
EOF

# Safe copy to tmp for verifier
cp "$RESULT_FILE" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."