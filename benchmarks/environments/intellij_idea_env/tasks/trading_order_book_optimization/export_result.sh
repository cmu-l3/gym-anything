#!/bin/bash
echo "=== Exporting trading_order_book_optimization result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/trading-orderbook"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run the tests and capture results
TEST_OUTPUT=$(timeout 120 su - ga -c \
    "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -f '$PROJECT_DIR/pom.xml' 2>&1" || true)
BUILD_EXIT=$?
BUILD_SUCCESS="false"
[ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"

# Read surefire XML reports
SUREFIRE_DIR="$PROJECT_DIR/target/surefire-reports"
TESTS_RUN=0
TESTS_FAILED=0
TESTS_ERROR=0

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

# Read source file content
ORDER_SOURCE=""
BOOK_SOURCE=""
ENGINE_SOURCE=""
if [ -f "$PROJECT_DIR/src/main/java/com/trading/Order.java" ]; then
    ORDER_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/trading/Order.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/trading/OrderBook.java" ]; then
    BOOK_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/trading/OrderBook.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/trading/MatchingEngine.java" ]; then
    ENGINE_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/trading/MatchingEngine.java")
fi

# Compute test file checksum
TEST_CHECKSUM=$(md5sum "$PROJECT_DIR/src/test/java/com/trading/OrderBookTest.java" \
    2>/dev/null | cut -d' ' -f1 || echo "")
INITIAL_TEST_CHECKSUM=$(cat /tmp/initial_test_checksum.txt 2>/dev/null | awk '{print $1}' || echo "")

# JSON-escape content
ORDER_ESCAPED=$(echo "$ORDER_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BOOK_ESCAPED=$(echo "$BOOK_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ENGINE_ESCAPED=$(echo "$ENGINE_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -40 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "tests_run": $TESTS_RUN,
    "tests_failed": $TESTS_FAILED,
    "tests_error": $TESTS_ERROR,
    "test_checksum_initial": "$INITIAL_TEST_CHECKSUM",
    "test_checksum_current": "$TEST_CHECKSUM",
    "order_source": $ORDER_ESCAPED,
    "orderbook_source": $BOOK_ESCAPED,
    "engine_source": $ENGINE_ESCAPED,
    "mvn_output": $OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "tests_run=$TESTS_RUN failures=$TESTS_FAILED errors=$TESTS_ERROR"
echo "=== Export complete ==="
