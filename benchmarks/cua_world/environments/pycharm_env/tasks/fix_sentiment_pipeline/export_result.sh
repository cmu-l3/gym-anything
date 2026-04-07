#!/bin/bash
echo "=== Exporting fix_sentiment_pipeline Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_sentiment_pipeline"
PROJECT_DIR="/home/ga/PycharmProjects/sentiment_pipeline"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
HIDDEN_EVAL_SCRIPT="/var/lib/sentiment_pipeline/evaluate_model.py"

# Take final screenshot
take_screenshot /tmp/${TASK_NAME}_final.png

# 1. Run visible tests
echo "Running visible tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# Check specific tests
NEGATION_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_negation_preservation PASSED" && NEGATION_PASS=true

SHORT_WORDS_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_short_words_included PASSED" && SHORT_WORDS_PASS=true

LOGIC_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_prediction_logic PASSED" && LOGIC_PASS=true

# 2. Run hidden evaluation
echo "Running hidden evaluation..."
EVAL_OUTPUT=$(python3 "$HIDDEN_EVAL_SCRIPT" 2>&1)
ACCURACY=$(echo "$EVAL_OUTPUT" | grep "ACCURACY:" | cut -d: -f2)
F1_SCORE=$(echo "$EVAL_OUTPUT" | grep "F1:" | cut -d: -f2)

# Default to 0 if failed
if [ -z "$ACCURACY" ]; then ACCURACY="0.0"; fi
if [ -z "$F1_SCORE" ]; then F1_SCORE="0.0"; fi

# 3. Static analysis checks (to verify specific bugs were fixed in code)
# Bug 1: Negation words in stopwords
PREPROCESS_FILE="$PROJECT_DIR/pipeline/preprocess.py"
BUG1_FIXED=false
if grep -q "ENGLISH_STOP_WORDS" "$PREPROCESS_FILE"; then
    # Check if they filter out 'not' from stopwords list
    if grep -qE "stop_words.*remove.*not|difference.*not|stop_words.*=.*\[.*not.*in.*stop_words" "$PREPROCESS_FILE" || \
       grep -qE "stop_words.*-.*\{.*not.*\}|stop_words.*-.*\[.*not.*\]" "$PREPROCESS_FILE"; then
        BUG1_FIXED=true
    # Or checks if they don't use stop words at all
    elif ! grep -q "stop_words" "$PREPROCESS_FILE"; then
        BUG1_FIXED=true
    fi
fi
# Alternative: check if test passed (more reliable than regex on code)
[ "$NEGATION_PASS" = "true" ] && BUG1_FIXED=true

# Bug 2: Regex pattern
FEATURES_FILE="$PROJECT_DIR/pipeline/features.py"
BUG2_FIXED=false
# Original was \b[a-zA-Z]{5,}\b. New should be shorter, e.g. {2,} or just \b\w\w+\b
if ! grep -q "{5,}" "$FEATURES_FILE"; then
    BUG2_FIXED=true
fi
[ "$SHORT_WORDS_PASS" = "true" ] && BUG2_FIXED=true

# Bug 3: Inverted logic
CLASSIFIER_FILE="$PROJECT_DIR/pipeline/classifier.py"
BUG3_FIXED=false
# Original: if prob_positive < 0.5: return "Positive"
# Fixed: if prob_positive > 0.5 (or >=) or inverted return
if grep -q "prob_positive > 0.5" "$CLASSIFIER_FILE" || \
   grep -q "prob_positive >= 0.5" "$CLASSIFIER_FILE"; then
    BUG3_FIXED=true
fi
# Logic test covers this
[ "$LOGIC_PASS" = "true" ] && BUG3_FIXED=true

# 4. Generate JSON result
cat > "$RESULT_FILE" << EOF
{
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "negation_test_pass": $NEGATION_PASS,
    "short_words_test_pass": $SHORT_WORDS_PASS,
    "logic_test_pass": $LOGIC_PASS,
    "hidden_accuracy": $ACCURACY,
    "hidden_f1": $F1_SCORE,
    "bug1_fixed": $BUG1_FIXED,
    "bug2_fixed": $BUG2_FIXED,
    "bug3_fixed": $BUG3_FIXED
}
EOF

echo "Result generated at $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="