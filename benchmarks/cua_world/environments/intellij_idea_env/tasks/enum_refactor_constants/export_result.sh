#!/bin/bash
echo "=== Exporting enum_refactor_constants result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/payment-processor"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Run Maven Tests and capture output
echo "Running tests..."
cd "$PROJECT_DIR"

# Run tests and capture both stdout and exit code
# We use 'clean test' to ensure no stale results
mvn clean test > /tmp/mvn_output.log 2>&1
MVN_EXIT_CODE=$?

# 3. Parse Test Results
TESTS_RUN=0
TESTS_FAILURES=0
TESTS_ERRORS=0
TESTS_SKIPPED=0

if [ -d "target/surefire-reports" ]; then
    for report in target/surefire-reports/*.xml; do
        if [ -f "$report" ]; then
            run=$(grep -oP 'tests="\K\d+' "$report" | head -1)
            fail=$(grep -oP 'failures="\K\d+' "$report" | head -1)
            err=$(grep -oP 'errors="\K\d+' "$report" | head -1)
            skip=$(grep -oP 'skipped="\K\d+' "$report" | head -1)
            
            TESTS_RUN=$((TESTS_RUN + ${run:-0}))
            TESTS_FAILURES=$((TESTS_FAILURES + ${fail:-0}))
            TESTS_ERRORS=$((TESTS_ERRORS + ${err:-0}))
            TESTS_SKIPPED=$((TESTS_SKIPPED + ${skip:-0}))
        fi
    done
fi

# 4. Read Source Files for Programmatic Verification
# We use python to safely JSON-escape file contents
read_file_escaped() {
    if [ -f "$1" ]; then
        python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" < "$1"
    else
        echo "null"
    fi
}

PAYMENT_TYPE_CONTENT=$(read_file_escaped "$PROJECT_DIR/src/main/java/com/payments/model/PaymentType.java")
PROCESSOR_CONTENT=$(read_file_escaped "$PROJECT_DIR/src/main/java/com/payments/processor/PaymentProcessor.java")
CALCULATOR_CONTENT=$(read_file_escaped "$PROJECT_DIR/src/main/java/com/payments/fees/FeeCalculator.java")
VALIDATOR_CONTENT=$(read_file_escaped "$PROJECT_DIR/src/main/java/com/payments/validation/PaymentValidator.java")
REPORT_CONTENT=$(read_file_escaped "$PROJECT_DIR/src/main/java/com/payments/report/PaymentReport.java")
TEST_CONTENT=$(read_file_escaped "$PROJECT_DIR/src/test/java/com/payments/processor/PaymentProcessorTest.java")

# Check if old constants file still exists or has content
CONSTANTS_FILE="$PROJECT_DIR/src/main/java/com/payments/constants/PaymentConstants.java"
CONSTANTS_EXISTS="false"
CONSTANTS_CONTENT="null"
if [ -f "$CONSTANTS_FILE" ]; then
    CONSTANTS_EXISTS="true"
    CONSTANTS_CONTENT=$(read_file_escaped "$CONSTANTS_FILE")
fi

# 5. Build Result JSON
cat > /tmp/result_data.json << EOF
{
    "mvn_exit_code": $MVN_EXIT_CODE,
    "tests_run": $TESTS_RUN,
    "tests_failures": $TESTS_FAILURES,
    "tests_errors": $TESTS_ERRORS,
    "tests_skipped": $TESTS_SKIPPED,
    "files": {
        "PaymentType.java": $PAYMENT_TYPE_CONTENT,
        "PaymentProcessor.java": $PROCESSOR_CONTENT,
        "FeeCalculator.java": $CALCULATOR_CONTENT,
        "PaymentValidator.java": $VALIDATOR_CONTENT,
        "PaymentReport.java": $REPORT_CONTENT,
        "PaymentProcessorTest.java": $TEST_CONTENT,
        "PaymentConstants.java": $CONSTANTS_CONTENT
    },
    "constants_file_exists": $CONSTANTS_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="