#!/bin/bash
echo "=== Exporting debug_sales_etl Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="debug_sales_etl"
PROJECT_DIR="/home/ga/PycharmProjects/sales_etl"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# Run the full test suite as the ga user and capture output + exit code
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

# Count how many tests passed and failed
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

# Determine overall: all 7 tests pass = exit 0
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# --- Check Bug 1 fix: parse_date should use "%Y-%m-%d" ---
TRANSFORM_FILE="$PROJECT_DIR/etl/transform.py"
BUG1_FIXED=false
if grep -q '"%Y-%m-%d"' "$TRANSFORM_FILE" 2>/dev/null && \
   ! grep -q '"%m/%d/%Y"' "$TRANSFORM_FILE" 2>/dev/null; then
    BUG1_FIXED=true
fi

# --- Check Bug 2 fix: apply_discount should use (1 - discount_pct/100) ---
BUG2_FIXED=false
if grep -qE 'unit_price\s*\*\s*\(?\s*1\s*-\s*discount_pct\s*/\s*100\s*\)?' "$TRANSFORM_FILE" 2>/dev/null; then
    BUG2_FIXED=true
fi

# --- Check Bug 3 fix: save_transaction INSERT column order ---
LOAD_FILE="$PROJECT_DIR/etl/load.py"
BUG3_FIXED=false
# The correct order is (product_id, quantity, unit_price, ...) matching the INSERT columns
# We verify the tuple in execute() no longer has quantity/unit_price swapped
# The correct code should have unit_price BEFORE quantity in the tuple matching:
# INSERT INTO transactions (product_id, quantity, unit_price, discount_pct, total_amount, sale_date)
# VALUES (txn.product_id, txn.quantity, txn.unit_price, ...)
# The buggy code had (txn.product_id, txn.unit_price, txn.quantity, ...)
if grep -q 'txn\.quantity' "$LOAD_FILE" 2>/dev/null && \
   grep -q 'txn\.unit_price' "$LOAD_FILE" 2>/dev/null; then
    # Check that quantity comes before unit_price in the tuple
    LOAD_CONTENT=$(cat "$LOAD_FILE" 2>/dev/null || echo "")
    # Extract the execute() call lines and check order
    EXECUTE_BLOCK=$(echo "$LOAD_CONTENT" | grep -A5 "cursor.execute" | tr '\n' ' ')
    # In correct code, txn.quantity appears before txn.unit_price in the values tuple
    QUANTITY_POS=$(echo "$EXECUTE_BLOCK" | grep -ob 'txn\.quantity' | head -1 | cut -d: -f1)
    UNIT_PRICE_POS=$(echo "$EXECUTE_BLOCK" | grep -ob 'txn\.unit_price' | head -1 | cut -d: -f1)
    if [ -n "$QUANTITY_POS" ] && [ -n "$UNIT_PRICE_POS" ] && [ "$QUANTITY_POS" -lt "$UNIT_PRICE_POS" ]; then
        BUG3_FIXED=true
    fi
fi

# Also check via specific test result
TEST_LOAD_PASS=false
if echo "$PYTEST_OUTPUT" | grep -q "test_save_and_retrieve_quantity PASSED"; then
    TEST_LOAD_PASS=true
    BUG3_FIXED=true
fi

# Check individual test results
TEST_PARSE_DATE_PASS=false
TEST_DISCOUNT_PASS=false
echo "$PYTEST_OUTPUT" | grep -q "test_parse_date_iso_format PASSED" && TEST_PARSE_DATE_PASS=true
echo "$PYTEST_OUTPUT" | grep -q "test_apply_discount_ten_percent PASSED" && TEST_DISCOUNT_PASS=true
echo "$PYTEST_OUTPUT" | grep -q "test_save_and_retrieve_quantity PASSED" && TEST_LOAD_PASS=true

# Check that the previously-passing tests still pass (no regression)
NO_REGRESSION=false
REGRESSION_CHECK=true
for test_name in "test_read_csv_returns_rows" "test_record_has_required_fields" "test_numeric_fields_are_floats" \
                 "test_parse_date_returns_datetime" "test_apply_no_discount"; do
    if ! echo "$PYTEST_OUTPUT" | grep -q "${test_name} PASSED"; then
        REGRESSION_CHECK=false
        break
    fi
done
[ "$REGRESSION_CHECK" = "true" ] && NO_REGRESSION=true

# Compute score
SCORE=0
[ "$BUG1_FIXED" = "true" ] && SCORE=$((SCORE + 30))
[ "$BUG2_FIXED" = "true" ] && SCORE=$((SCORE + 30))
[ "$BUG3_FIXED" = "true" ] && SCORE=$((SCORE + 30))
[ "$NO_REGRESSION" = "true" ] && SCORE=$((SCORE + 10))
[ $SCORE -gt 100 ] && SCORE=100

# Write result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_total": $TESTS_TOTAL,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_fixed_parse_date": $BUG1_FIXED,
    "bug2_fixed_apply_discount": $BUG2_FIXED,
    "bug3_fixed_save_transaction": $BUG3_FIXED,
    "test_parse_date_pass": $TEST_PARSE_DATE_PASS,
    "test_discount_pass": $TEST_DISCOUNT_PASS,
    "test_load_pass": $TEST_LOAD_PASS,
    "no_regression": $NO_REGRESSION,
    "computed_score": $SCORE
}
EOF

echo "Pytest exit code: $PYTEST_EXIT_CODE"
echo "Tests: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "Bug 1 (parse_date) fixed: $BUG1_FIXED"
echo "Bug 2 (apply_discount) fixed: $BUG2_FIXED"
echo "Bug 3 (save_transaction) fixed: $BUG3_FIXED"
echo "No regression: $NO_REGRESSION"
echo "Computed score: $SCORE"
echo "=== Export Complete ==="
