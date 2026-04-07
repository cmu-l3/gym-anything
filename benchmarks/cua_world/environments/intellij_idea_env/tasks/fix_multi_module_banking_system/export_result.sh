#!/bin/bash
echo "=== Exporting fix_multi_module_banking_system result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/bank-ledger-system"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run the tests from parent POM and capture results
# Use -fn (fail-never) so all modules run even if upstream tests fail
TEST_OUTPUT=$(timeout 180 su - ga -c \
    "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -fn -f '$PROJECT_DIR/pom.xml' 2>&1" || true)
BUILD_EXIT=$?
BUILD_SUCCESS="false"
[ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"

# Aggregate surefire XML reports from ALL modules
TESTS_RUN=0
TESTS_FAILED=0
TESTS_ERROR=0

for module in bank-commons bank-ledger bank-processing; do
    SUREFIRE_DIR="$PROJECT_DIR/$module/target/surefire-reports"
    if [ -d "$SUREFIRE_DIR" ]; then
        for xml in "$SUREFIRE_DIR"/TEST-*.xml; do
            [ -f "$xml" ] || continue
            run=$(grep -o 'tests="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
            fail=$(grep -o 'failures="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
            err=$(grep -o 'errors="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
            TESTS_RUN=$((TESTS_RUN + ${run:-0}))
            TESTS_FAILED=$((TESTS_FAILED + ${fail:-0}))
            TESTS_ERROR=$((TESTS_ERROR + ${err:-0}))
        done
    fi
done

# Read source file content from all modules
read_file() {
    if [ -f "$1" ]; then
        cat "$1"
    else
        echo ""
    fi
}

BALANCE_CALC_SRC=$(read_file "$PROJECT_DIR/bank-ledger/src/main/java/com/bank/ledger/BalanceCalculator.java")
LEDGER_SRC=$(read_file "$PROJECT_DIR/bank-ledger/src/main/java/com/bank/ledger/Ledger.java")
TX_PROCESSOR_SRC=$(read_file "$PROJECT_DIR/bank-processing/src/main/java/com/bank/processing/TransactionProcessor.java")
PARENT_POM=$(read_file "$PROJECT_DIR/pom.xml")
COMMONS_POM=$(read_file "$PROJECT_DIR/bank-commons/pom.xml")
LEDGER_POM=$(read_file "$PROJECT_DIR/bank-ledger/pom.xml")
PROCESSING_POM=$(read_file "$PROJECT_DIR/bank-processing/pom.xml")

# Compute current test file checksums
COMMONS_TEST_CKSUM=$(md5sum "$PROJECT_DIR/bank-commons/src/test/java/com/bank/commons/CommonsTest.java" \
    2>/dev/null | cut -d' ' -f1 || echo "")
LEDGER_TEST_CKSUM=$(md5sum "$PROJECT_DIR/bank-ledger/src/test/java/com/bank/ledger/LedgerTest.java" \
    2>/dev/null | cut -d' ' -f1 || echo "")
PROCESSING_TEST_CKSUM=$(md5sum "$PROJECT_DIR/bank-processing/src/test/java/com/bank/processing/ProcessingTest.java" \
    2>/dev/null | cut -d' ' -f1 || echo "")

# Read initial checksums
INIT_COMMONS_CKSUM=$(grep "CommonsTest.java" /tmp/initial_test_checksums.txt 2>/dev/null | awk '{print $1}' || echo "")
INIT_LEDGER_CKSUM=$(grep "LedgerTest.java" /tmp/initial_test_checksums.txt 2>/dev/null | awk '{print $1}' || echo "")
INIT_PROCESSING_CKSUM=$(grep "ProcessingTest.java" /tmp/initial_test_checksums.txt 2>/dev/null | awk '{print $1}' || echo "")

# JSON-escape content
json_escape() {
    echo "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

BALANCE_CALC_ESCAPED=$(json_escape "$BALANCE_CALC_SRC")
LEDGER_ESCAPED=$(json_escape "$LEDGER_SRC")
TX_PROCESSOR_ESCAPED=$(json_escape "$TX_PROCESSOR_SRC")
PARENT_POM_ESCAPED=$(json_escape "$PARENT_POM")
COMMONS_POM_ESCAPED=$(json_escape "$COMMONS_POM")
LEDGER_POM_ESCAPED=$(json_escape "$LEDGER_POM")
PROCESSING_POM_ESCAPED=$(json_escape "$PROCESSING_POM")
OUTPUT_ESCAPED=$(json_escape "$(echo "$TEST_OUTPUT" | tail -60)")

RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "tests_run": $TESTS_RUN,
    "tests_failed": $TESTS_FAILED,
    "tests_error": $TESTS_ERROR,
    "test_checksums": {
        "commons_initial": "$INIT_COMMONS_CKSUM",
        "commons_current": "$COMMONS_TEST_CKSUM",
        "ledger_initial": "$INIT_LEDGER_CKSUM",
        "ledger_current": "$LEDGER_TEST_CKSUM",
        "processing_initial": "$INIT_PROCESSING_CKSUM",
        "processing_current": "$PROCESSING_TEST_CKSUM"
    },
    "sources": {
        "balance_calculator": $BALANCE_CALC_ESCAPED,
        "ledger": $LEDGER_ESCAPED,
        "transaction_processor": $TX_PROCESSOR_ESCAPED
    },
    "poms": {
        "parent": $PARENT_POM_ESCAPED,
        "commons": $COMMONS_POM_ESCAPED,
        "ledger": $LEDGER_POM_ESCAPED,
        "processing": $PROCESSING_POM_ESCAPED
    },
    "mvn_output": $OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "tests_run=$TESTS_RUN failures=$TESTS_FAILED errors=$TESTS_ERROR"
echo "=== Export complete ==="
