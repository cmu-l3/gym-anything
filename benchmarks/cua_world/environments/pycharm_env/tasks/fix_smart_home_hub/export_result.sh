#!/bin/bash
echo "=== Exporting fix_smart_home_hub Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_smart_home_hub"
PROJECT_DIR="/home/ga/PycharmProjects/smarthub"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run tests
echo "Running tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# --- Static Analysis Checks ---

# Bug 1: engine.py - Check for asyncio.sleep vs time.sleep
BUG1_FIXED=false
ENGINE_CONTENT=$(cat "$PROJECT_DIR/core/engine.py" 2>/dev/null)
if echo "$ENGINE_CONTENT" | grep -q "await asyncio.sleep" && ! echo "$ENGINE_CONTENT" | grep -q "time.sleep"; then
    BUG1_FIXED=true
fi
# Double check with test result
if echo "$PYTEST_OUTPUT" | grep -q "test_scene_execution_non_blocking PASSED"; then
    BUG1_FIXED=true
fi

# Bug 2: rules.py - Check for parentheses or logic fix
BUG2_FIXED=false
RULES_CONTENT=$(cat "$PROJECT_DIR/core/rules.py" 2>/dev/null)
# Look for parens around (dark or evening) OR (is_dark or is_evening)
if echo "$RULES_CONTENT" | grep -q "motion and (.*dark.*or.*evening.*)"; then
    BUG2_FIXED=true
fi
if echo "$PYTEST_OUTPUT" | grep -q "test_trigger_just_evening_no_motion PASSED"; then
    BUG2_FIXED=true
fi

# Bug 3: devices.py - Check for camelCase keys
BUG3_FIXED=false
DEVICES_CONTENT=$(cat "$PROJECT_DIR/core/devices.py" 2>/dev/null)
if echo "$DEVICES_CONTENT" | grep -q "brightnessLevel"; then
    BUG3_FIXED=true
fi
if echo "$PYTEST_OUTPUT" | grep -q "test_bulb_state_update PASSED"; then
    BUG3_FIXED=true
fi

# Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_fixed": $BUG1_FIXED,
    "bug2_fixed": $BUG2_FIXED,
    "bug3_fixed": $BUG3_FIXED,
    "pytest_exit_code": $PYTEST_EXIT_CODE
}
EOF

# Move to safe location
cp "$RESULT_FILE" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="