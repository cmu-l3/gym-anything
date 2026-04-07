#!/bin/bash
echo "=== Exporting fix_meeting_scheduler Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_meeting_scheduler"
PROJECT_DIR="/home/ga/PycharmProjects/meeting_scheduler"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# Run tests
cd "$PROJECT_DIR" || exit 1
# Ensure deps are installed (tzdata)
pip3 install pytest tzdata -q 2>/dev/null || true

PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

CORE_FILE="$PROJECT_DIR/scheduler/core.py"
CORE_CONTENT=$(cat "$CORE_FILE" 2>/dev/null || echo "")

# --- Verification Logic ---

# Bug 1: Overlap Logic
# Check if enclosing test passed
TEST_OVERLAP_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_overlap_enclosing PASSED" && TEST_OVERLAP_PASS=true

# Static check for overlap logic improvement
# Looking for something that handles the enclosing case.
# Common correct patterns: 
# 1. max(start, other_start) < min(end, other_end)
# 2. start < other_end AND end > other_start
# 3. not (end <= other_start OR start >= other_end)
OVERLAP_STATIC_FIX=false
if grep -q "max(.*start.*min(.*end" "$CORE_FILE" || \
   grep -q "start.*<.*meeting.end.*and.*end.*>.*meeting.start" "$CORE_FILE"; then
    OVERLAP_STATIC_FIX=true
fi

# Bug 2: Timezone/Working Hours
# Check if Tokyo tests passed
TEST_TIMEZONE_PASS=false
if echo "$PYTEST_OUTPUT" | grep -q "test_working_hours_tokyo_morning PASSED" && \
   echo "$PYTEST_OUTPUT" | grep -q "test_working_hours_tokyo_night PASSED"; then
    TEST_TIMEZONE_PASS=true
fi

# Static check for timezone conversion
# Should see astimezone() being used with the user's timezone
TIMEZONE_STATIC_FIX=false
if grep -q "astimezone" "$CORE_FILE" && grep -q "ZoneInfo" "$CORE_FILE"; then
    TIMEZONE_STATIC_FIX=true
fi

# Bug 3: Future Time Validation (Naive vs Aware)
TEST_FUTURE_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_validate_future_time_bug PASSED" && TEST_FUTURE_PASS=true

# Static check
# Should use datetime.now(timezone.utc) or similar aware construction
FUTURE_STATIC_FIX=false
if grep -q "datetime.now(.*timezone.utc.*)" "$CORE_FILE" || \
   grep -q "datetime.now(.*UTC.*)" "$CORE_FILE"; then
    FUTURE_STATIC_FIX=true
fi

# Check for Regression
REGRESSION_PASS=true
# Simply checks if ALL tests passed. If any failed, regression or incomplete fix.
[ "$ALL_TESTS_PASS" = "false" ] && REGRESSION_PASS=false

cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_overlap_test_pass": $TEST_OVERLAP_PASS,
    "bug1_overlap_static_fix": $OVERLAP_STATIC_FIX,
    "bug2_timezone_test_pass": $TEST_TIMEZONE_PASS,
    "bug2_timezone_static_fix": $TIMEZONE_STATIC_FIX,
    "bug3_future_test_pass": $TEST_FUTURE_PASS,
    "bug3_future_static_fix": $FUTURE_STATIC_FIX,
    "regression_pass": $REGRESSION_PASS
}
EOF

echo "Tests: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "Result exported to $RESULT_FILE"