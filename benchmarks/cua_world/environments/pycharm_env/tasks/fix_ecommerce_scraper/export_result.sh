#!/bin/bash
echo "=== Exporting fix_ecommerce_scraper Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_ecommerce_scraper"
PROJECT_DIR="/home/ga/PycharmProjects/shop_scraper"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Run Tests
# Run verbose to capture individual test names
echo "Running tests..."
cd "$PROJECT_DIR" || exit 1
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

# 3. Analyze Test Results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# 4. Specific Check Results (Did specific categories pass?)
PASS_TITLE=false
PASS_PRICE=false
PASS_AVAILABILITY=false
PASS_SPECS=false

echo "$PYTEST_OUTPUT" | grep -q "test_extract_title PASSED" && PASS_TITLE=true
echo "$PYTEST_OUTPUT" | grep -q "test_extract_price PASSED" && PASS_PRICE=true
echo "$PYTEST_OUTPUT" | grep -q "test_extract_availability PASSED" && PASS_AVAILABILITY=true
echo "$PYTEST_OUTPUT" | grep -q "test_extract_specs PASSED" && PASS_SPECS=true

# 5. Static Analysis (Safety Check)
# Ensure they aren't just hardcoding the return values for the main file
# We check if BeautifulSoup find/select calls are changed
PARSER_FILE="$PROJECT_DIR/scraper/parsers.py"
USES_DATA_TESTID=false
USES_CLASS_SELECTOR=false

if grep -q 'data-testid' "$PARSER_FILE" || grep -q 'attrs={"data-testid"' "$PARSER_FILE"; then
    USES_DATA_TESTID=true
fi

# 6. JSON Export
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "pass_title": $PASS_TITLE,
    "pass_price": $PASS_PRICE,
    "pass_availability": $PASS_AVAILABILITY,
    "pass_specs": $PASS_SPECS,
    "uses_data_testid": $USES_DATA_TESTID
}
EOF

echo "Export complete. Tests passed: $TESTS_PASSED/$TESTS_TOTAL"