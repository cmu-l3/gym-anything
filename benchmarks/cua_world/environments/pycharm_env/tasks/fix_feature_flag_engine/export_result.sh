#!/bin/bash
echo "=== Exporting fix_feature_flag_engine result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_feature_flag_engine"
PROJECT_DIR="/home/ga/PycharmProjects/feature_flags"
RESULT_FILE="/tmp/task_result.json"

# Take screenshot
take_screenshot /tmp/task_final.png

# Run tests
echo "Running tests..."
cd "$PROJECT_DIR"
PYTEST_OUTPUT=$(su - ga -c "python3 -m pytest tests/test_engine.py -v" 2>&1)
PYTEST_EXIT=$?

# Analyze results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c "PASSED")
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c "FAILED")

# Check specific bug fixes

# Bug 1: Float support
# Check if Lexer has code handling '.' inside number parsing or similar logic
LEXER_CONTENT=$(cat "$PROJECT_DIR/flags/lexer.py")
BUG1_FIXED=false
if echo "$PYTEST_OUTPUT" | grep -q "test_tokenize_floats PASSED"; then
    BUG1_FIXED=true
fi

# Bug 2: Precedence
# Check if AND precedence > OR precedence (OR=20, AND should be >20)
PARSER_CONTENT=$(cat "$PROJECT_DIR/flags/parser.py")
BUG2_FIXED=false
if echo "$PYTEST_OUTPUT" | grep -q "test_precedence_mixed PASSED"; then
    BUG2_FIXED=true
fi
# Static check: ensure AND > OR
AND_PREC=$(echo "$PARSER_CONTENT" | grep "TokenType.AND:" | grep -o "[0-9]*")
OR_PREC=$(echo "$PARSER_CONTENT" | grep "TokenType.OR:" | grep -o "[0-9]*")
if [ -n "$AND_PREC" ] && [ -n "$OR_PREC" ]; then
    if [ "$AND_PREC" -gt "$OR_PREC" ]; then
        echo "Static check: AND($AND_PREC) > OR($OR_PREC)"
    fi
fi

# Bug 3: Short-circuit
# Check if Evaluator checks left side before evaluating right
EVAL_CONTENT=$(cat "$PROJECT_DIR/flags/evaluator.py")
BUG3_FIXED=false
if echo "$PYTEST_OUTPUT" | grep -q "test_short_circuit_and PASSED" && \
   echo "$PYTEST_OUTPUT" | grep -q "test_short_circuit_or PASSED"; then
    BUG3_FIXED=true
fi

# Prepare JSON
cat > "$RESULT_FILE" << EOF
{
    "tests_passed_count": $TESTS_PASSED,
    "tests_failed_count": $TESTS_FAILED,
    "pytest_exit_code": $PYTEST_EXIT,
    "bug1_float_fixed": $BUG1_FIXED,
    "bug2_precedence_fixed": $BUG2_FIXED,
    "bug3_short_circuit_fixed": $BUG3_FIXED,
    "timestamp": $(date +%s)
}
EOF

# Secure permissions
chmod 644 "$RESULT_FILE"

echo "Export complete."
cat "$RESULT_FILE"