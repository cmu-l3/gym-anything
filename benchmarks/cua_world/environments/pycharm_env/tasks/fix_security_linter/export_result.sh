#!/bin/bash
echo "=== Exporting fix_security_linter Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_security_linter"
PROJECT_DIR="/home/ga/PycharmProjects/security_linter"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
VISITORS_FILE="$PROJECT_DIR/linter/visitors.py"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Run Test Suite
echo "Running pytest..."
cd "$PROJECT_DIR" || exit 1
# Run verbose, show locals on failure
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

# 3. Parse Test Results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# 4. Analyze Code Fixes (Static Analysis of Agent's Solution)

# Check Bug 1: Recursion in visit_FunctionDef
# Agent must add 'generic_visit' to visit_FunctionDef
BUG1_FIXED=false
if grep -A 5 "def visit_FunctionDef" "$VISITORS_FILE" | grep -q "generic_visit"; then
    BUG1_FIXED=true
fi

# Check Bug 2: False Positive in SecretVisitor
# Agent must check type of node.value (isinstance/Constant/Str)
BUG2_FIXED=false
if grep -q "isinstance.*value" "$VISITORS_FILE" || grep -q "ast\.Constant" "$VISITORS_FILE" || grep -q "ast\.Str" "$VISITORS_FILE"; then
    BUG2_FIXED=true
fi
# Negative check: shouldn't just check name anymore
if grep -q "if 'password' in target_name" "$VISITORS_FILE" && ! grep -q "and" "$VISITORS_FILE"; then
    # This is a heuristic, verified by tests mostly
    :
fi

# Check Bug 3: shell=True check
# Agent must check .value attribute of the constant
BUG3_FIXED=false
if grep -q "\.value.*is True" "$VISITORS_FILE" || grep -q "\.value.*== True" "$VISITORS_FILE"; then
    BUG3_FIXED=true
fi

# 5. Check specific critical tests
TEST_NESTED_EVAL_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_detect_nested_eval PASSED" && TEST_NESTED_EVAL_PASS=true

TEST_SAFE_PWD_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_safe_password_assignment PASSED" && TEST_SAFE_PWD_PASS=true

TEST_SHELL_TRUE_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_subprocess_shell_true PASSED" && TEST_SHELL_TRUE_PASS=true

# 6. Safety Check: Verify tests weren't modified
# Compute hash of test file
TEST_HASH=$(md5sum "$PROJECT_DIR/tests/test_linter.py" | awk '{print $1}')
# Expected hash of the original test file provided in setup
# (In a real scenario we'd compare against a stored ground truth file, 
# here we'll just check if the file still exists and has roughly correct size)
TEST_FILE_SIZE=$(stat -c%s "$PROJECT_DIR/tests/test_linter.py")

# 7. Create Result JSON
# Escape output for JSON
PYTEST_ESCAPED=$(echo "$PYTEST_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_total": $TESTS_TOTAL,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_recursion_fixed": $BUG1_FIXED,
    "bug2_false_positive_fixed": $BUG2_FIXED,
    "bug3_shell_check_fixed": $BUG3_FIXED,
    "test_nested_eval_pass": $TEST_NESTED_EVAL_PASS,
    "test_safe_pwd_pass": $TEST_SAFE_PWD_PASS,
    "test_shell_true_pass": $TEST_SHELL_TRUE_PASS,
    "test_file_size": $TEST_FILE_SIZE,
    "pytest_output": $PYTEST_ESCAPED
}
EOF

echo "Result saved to $RESULT_FILE"
echo "Tests Passed: $TESTS_PASSED / $TESTS_TOTAL"
echo "=== Export complete ==="