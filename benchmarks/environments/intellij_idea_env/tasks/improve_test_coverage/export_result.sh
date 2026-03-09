#!/bin/bash
echo "=== Exporting improve_test_coverage result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/fintech-risk-engine"
LOGIC_FILE="$PROJECT_DIR/src/main/java/com/fintech/risk/LoanRiskCalculator.java"
TEST_FILE="$PROJECT_DIR/src/test/java/com/fintech/risk/LoanRiskCalculatorTest.java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check Source Integrity (Anti-Gaming)
CURRENT_HASH=$(md5sum "$LOGIC_FILE" 2>/dev/null | awk '{print $1}')
INITIAL_HASH=$(cat /tmp/initial_logic_hash.txt 2>/dev/null)
SOURCE_INTACT="false"
if [ "$CURRENT_HASH" == "$INITIAL_HASH" ]; then
    SOURCE_INTACT="true"
fi

# 2. Run Tests and Generate JaCoCo Report
echo "Running tests and generating coverage report..."
cd "$PROJECT_DIR"
TEST_OUTPUT=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean test jacoco:report" 2>&1)
MVN_EXIT_CODE=$?

TESTS_PASSED="false"
if [ $MVN_EXIT_CODE -eq 0 ]; then
    TESTS_PASSED="true"
fi

# 3. Locate Coverage Report
JACOCO_XML="$PROJECT_DIR/target/site/jacoco/jacoco.xml"
REPORT_EXISTS="false"
if [ -f "$JACOCO_XML" ]; then
    REPORT_EXISTS="true"
    # Copy report to /tmp for easy access by verifier
    cp "$JACOCO_XML" /tmp/jacoco_report.xml
    chmod 644 /tmp/jacoco_report.xml
fi

# 4. Prepare Test File for Verification
if [ -f "$TEST_FILE" ]; then
    cp "$TEST_FILE" /tmp/final_test_file.java
    chmod 644 /tmp/final_test_file.java
fi

# 5. Capture Test Counts from Output
TESTS_RUN=0
if [ "$TESTS_PASSED" == "true" ]; then
    TESTS_RUN=$(echo "$TEST_OUTPUT" | grep -o "Tests run: [0-9]*" | head -1 | awk '{print $3}')
fi

# 6. Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "source_intact": $SOURCE_INTACT,
    "tests_passed": $TESTS_PASSED,
    "report_exists": $REPORT_EXISTS,
    "tests_run": ${TESTS_RUN:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="