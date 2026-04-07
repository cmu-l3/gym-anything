#!/bin/bash
echo "=== Exporting fix_drone_state_estimator Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_drone_state_estimator"
PROJECT_DIR="/home/ga/PycharmProjects/drone_estimator"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 1. Run Tests
echo "Running tests..."
cd "$PROJECT_DIR"
TEST_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/ -v 2>&1")
TEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$TEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$TEST_OUTPUT" | grep -c " FAILED" || true)

# Check specific tests
PASS_PREDICT=$(echo "$TEST_OUTPUT" | grep -q "test_predict_constant_velocity PASSED" && echo "true" || echo "false")
PASS_MATRIX=$(echo "$TEST_OUTPUT" | grep -q "test_gps_update_matrix PASSED" && echo "true" || echo "false")
PASS_COV=$(echo "$TEST_OUTPUT" | grep -q "test_covariance_reduction PASSED" && echo "true" || echo "false")

# 2. Run Evaluation Script
echo "Running evaluation..."
EVAL_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && python3 scripts/evaluate_trajectory.py 2>&1")
RMSE=$(echo "$EVAL_OUTPUT" | grep "Total Position RMSE:" | awk '{print $4}')
STATUS=$(echo "$EVAL_OUTPUT" | grep "STATUS:" | awk '{print $2}')

# 3. Static Code Analysis (Regex checks)
# Check for Bug 1 fix: dt multiplication in predict
CODE_FIX_1="false"
if grep -q "new_x\[0:3\] += self.x\[3:6\] \* dt" "$PROJECT_DIR/estimator/ekf.py"; then
    CODE_FIX_1="true"
fi

# Check for Bug 2 fix: H matrix indices
CODE_FIX_2="false"
if grep -q "H\[0, 0\] = 1" "$PROJECT_DIR/estimator/ekf.py" || grep -q "H\[0, 0\]=1" "$PROJECT_DIR/estimator/ekf.py"; then
    CODE_FIX_2="true"
fi
# Alternatively check that 3, 4, 5 are NOT set
if ! grep -q "H\[0, 3\]" "$PROJECT_DIR/estimator/ekf.py"; then
    CODE_FIX_2="true"
fi

# Check for Bug 3 fix: Covariance subtraction
CODE_FIX_3="false"
if grep -q "I - K @ H" "$PROJECT_DIR/estimator/ekf.py" || grep -q "I-K@H" "$PROJECT_DIR/estimator/ekf.py"; then
    CODE_FIX_3="true"
fi

# Create JSON Result
cat > "$RESULT_FILE" << EOF
{
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "pass_predict": $PASS_PREDICT,
    "pass_matrix": $PASS_MATRIX,
    "pass_cov": $PASS_COV,
    "rmse": "${RMSE:-999}",
    "eval_status": "$STATUS",
    "code_fix_1": $CODE_FIX_1,
    "code_fix_2": $CODE_FIX_2,
    "code_fix_3": $CODE_FIX_3
}
EOF

echo "Results exported to $RESULT_FILE"
cat "$RESULT_FILE"