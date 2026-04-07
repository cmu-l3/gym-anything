#!/bin/bash
echo "=== Exporting resolve_merge_conflicts result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="resolve_merge_conflicts"
PROJECT_DIR="/home/ga/PycharmProjects/motor_control"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_end.png

cd "$PROJECT_DIR"

# 1. Check for conflict markers in python files
# Returns 0 if found (bad), 1 if not found (good)
grep -r "<<<<<<<" control/*.py > /dev/null
CONFLICTS_REMAIN=$? # 0 = yes, 1 = no
if [ "$CONFLICTS_REMAIN" -eq 1 ]; then
    NO_CONFLICT_MARKERS="true"
else
    NO_CONFLICT_MARKERS="false"
fi

# 2. Check Git Status (Merge should be committed)
GIT_STATUS=$(git status --porcelain)
if [ -z "$GIT_STATUS" ]; then
    GIT_CLEAN="true"
else
    GIT_CLEAN="false"
fi

# 3. Check specific feature presence via grep (Simple static analysis)
PID_CONTENT=$(cat control/pid.py 2>/dev/null)
MOTOR_CONTENT=$(cat control/motor_driver.py 2>/dev/null)
FILTERS_CONTENT=$(cat control/filters.py 2>/dev/null)

HAS_ADAPTIVE=false
if echo "$PID_CONTENT" | grep -q "adaptive_rate" && echo "$PID_CONTENT" | grep -q "error_history"; then
    HAS_ADAPTIVE=true
fi

HAS_RAMP_AND_CLAMP=false
if echo "$MOTOR_CONTENT" | grep -q "ramp_rate" && echo "$MOTOR_CONTENT" | grep -q "max_speed"; then
    HAS_RAMP_AND_CLAMP=true
fi

HAS_NEW_FILTERS=false
if echo "$FILTERS_CONTENT" | grep -q "exponential_filter" && echo "$FILTERS_CONTENT" | grep -q "moving_average_filter"; then
    HAS_NEW_FILTERS=true
fi

# 4. Verify Tests haven't been tampered with
cd "$PROJECT_DIR/tests"
md5sum -c /tmp/tests_checksum.md5 > /dev/null 2>&1
TESTS_INTEGRITY=$? # 0 = match, 1 = mismatch
if [ "$TESTS_INTEGRITY" -eq 0 ]; then
    TESTS_UNMODIFIED="true"
else
    TESTS_UNMODIFIED="false"
fi

# 5. Run Tests
cd "$PROJECT_DIR"
# Run pytest and capture everything
PYTEST_OUTPUT=$(python3 -m pytest tests/ -v --tb=short 2>&1)
PYTEST_EXIT_CODE=$?

# Parse output
PASSED_PID=$(echo "$PYTEST_OUTPUT" | grep "test_pid.py" | grep "PASSED" | wc -l)
PASSED_MOTOR=$(echo "$PYTEST_OUTPUT" | grep "test_motor_driver.py" | grep "PASSED" | wc -l)
PASSED_FILTERS=$(echo "$PYTEST_OUTPUT" | grep "test_filters.py" | grep "PASSED" | wc -l)

TOTAL_PASSED=$(echo "$PYTEST_OUTPUT" | grep " PASSED" | wc -l)
TOTAL_TESTS=12

# Create JSON Result
cat > "$RESULT_FILE" << EOF
{
    "no_conflict_markers": $NO_CONFLICT_MARKERS,
    "git_clean": $GIT_CLEAN,
    "has_adaptive_features": $HAS_ADAPTIVE,
    "has_ramp_and_clamp": $HAS_RAMP_AND_CLAMP,
    "has_new_filters": $HAS_NEW_FILTERS,
    "tests_unmodified": $TESTS_UNMODIFIED,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "passed_pid_count": $PASSED_PID,
    "passed_motor_count": $PASSED_MOTOR,
    "passed_filters_count": $PASSED_FILTERS,
    "total_passed": $TOTAL_PASSED,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="