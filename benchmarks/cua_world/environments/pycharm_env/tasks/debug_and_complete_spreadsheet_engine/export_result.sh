#!/bin/bash
echo "=== Exporting debug_and_complete_spreadsheet_engine Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="debug_and_complete_spreadsheet_engine"
PROJECT_DIR="/home/ga/PycharmProjects/spreadsheet_engine"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# Run pytest
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_ERROR=$(echo "$PYTEST_OUTPUT" | grep -c " ERROR" || true)
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED + TESTS_ERROR))
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# Check if test files were modified (anti-gaming)
TESTS_MODIFIED=false
for tf in test_cell test_parser test_evaluator test_functions test_dependency test_formatter test_csv_io test_integration conftest; do
    TF_PATH="$PROJECT_DIR/tests/${tf}.py"
    if [ -f "$TF_PATH" ]; then
        TF_TS=$(stat -c %Y "$TF_PATH" 2>/dev/null || echo "0")
        if [ "$TF_TS" -gt "$TASK_START" ]; then
            TESTS_MODIFIED=true
            break
        fi
    fi
done

# Check if data files were modified
DATA_MODIFIED=false
for df in sales_data.csv employees.csv; do
    DF_PATH="$PROJECT_DIR/data/${df}"
    if [ -f "$DF_PATH" ]; then
        DF_TS=$(stat -c %Y "$DF_PATH" 2>/dev/null || echo "0")
        if [ "$DF_TS" -gt "$TASK_START" ]; then
            DATA_MODIFIED=true
            break
        fi
    fi
done

# Collect individual test results
TEST_CELL_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_cell.py" | grep -c "PASSED" || true)
TEST_CELL_TOTAL=$(echo "$PYTEST_OUTPUT" | grep -c "test_cell.py" || true)
TEST_PARSER_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_parser.py" | grep -c "PASSED" || true)
TEST_PARSER_TOTAL=$(echo "$PYTEST_OUTPUT" | grep -c "test_parser.py" || true)
TEST_EVAL_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_evaluator.py" | grep -c "PASSED" || true)
TEST_EVAL_TOTAL=$(echo "$PYTEST_OUTPUT" | grep -c "test_evaluator.py" || true)
TEST_FUNC_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_functions.py" | grep -c "PASSED" || true)
TEST_FUNC_TOTAL=$(echo "$PYTEST_OUTPUT" | grep -c "test_functions.py" || true)
TEST_DEP_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_dependency.py" | grep -c "PASSED" || true)
TEST_DEP_TOTAL=$(echo "$PYTEST_OUTPUT" | grep -c "test_dependency.py" || true)
TEST_FMT_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_formatter.py" | grep -c "PASSED" || true)
TEST_FMT_TOTAL=$(echo "$PYTEST_OUTPUT" | grep -c "test_formatter.py" || true)
TEST_CSV_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_csv_io.py" | grep -c "PASSED" || true)
TEST_CSV_TOTAL=$(echo "$PYTEST_OUTPUT" | grep -c "test_csv_io.py" || true)
TEST_INT_PASS=$(echo "$PYTEST_OUTPUT" | grep "test_integration.py" | grep -c "PASSED" || true)
TEST_INT_TOTAL=$(echo "$PYTEST_OUTPUT" | grep -c "test_integration.py" || true)

# Check which source files were modified (for evidence of work)
CELL_MODIFIED=false
PARSER_MODIFIED=false
EVALUATOR_MODIFIED=false
FUNCTIONS_MODIFIED=false
DEPENDENCY_MODIFIED=false
CSV_IO_MODIFIED=false

for src_pair in "cell.py:CELL_MODIFIED" "parser.py:PARSER_MODIFIED" "evaluator.py:EVALUATOR_MODIFIED" \
                "functions.py:FUNCTIONS_MODIFIED" "dependency.py:DEPENDENCY_MODIFIED" "csv_io.py:CSV_IO_MODIFIED"; do
    SRC_FILE="${src_pair%%:*}"
    VAR_NAME="${src_pair##*:}"
    SRC_PATH="$PROJECT_DIR/engine/${SRC_FILE}"
    if [ -f "$SRC_PATH" ]; then
        SRC_TS=$(stat -c %Y "$SRC_PATH" 2>/dev/null || echo "0")
        if [ "$SRC_TS" -gt "$TASK_START" ]; then
            eval "${VAR_NAME}=true"
        fi
    fi
done

cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_error": $TESTS_ERROR,
    "total_tests": $TOTAL_TESTS,
    "all_tests_pass": $ALL_TESTS_PASS,
    "tests_modified": $TESTS_MODIFIED,
    "data_modified": $DATA_MODIFIED,
    "per_file": {
        "test_cell": {"passed": $TEST_CELL_PASS, "total": $TEST_CELL_TOTAL},
        "test_parser": {"passed": $TEST_PARSER_PASS, "total": $TEST_PARSER_TOTAL},
        "test_evaluator": {"passed": $TEST_EVAL_PASS, "total": $TEST_EVAL_TOTAL},
        "test_functions": {"passed": $TEST_FUNC_PASS, "total": $TEST_FUNC_TOTAL},
        "test_dependency": {"passed": $TEST_DEP_PASS, "total": $TEST_DEP_TOTAL},
        "test_formatter": {"passed": $TEST_FMT_PASS, "total": $TEST_FMT_TOTAL},
        "test_csv_io": {"passed": $TEST_CSV_PASS, "total": $TEST_CSV_TOTAL},
        "test_integration": {"passed": $TEST_INT_PASS, "total": $TEST_INT_TOTAL}
    },
    "source_modifications": {
        "cell_py": $CELL_MODIFIED,
        "parser_py": $PARSER_MODIFIED,
        "evaluator_py": $EVALUATOR_MODIFIED,
        "functions_py": $FUNCTIONS_MODIFIED,
        "dependency_py": $DEPENDENCY_MODIFIED,
        "csv_io_py": $CSV_IO_MODIFIED
    }
}
EOF

echo "--- Result Summary ---"
echo "Tests: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_ERROR errors (total: $TOTAL_TESTS)"
echo "Tests modified: $TESTS_MODIFIED"
echo "Data modified: $DATA_MODIFIED"
echo "Result saved to $RESULT_FILE"
echo "=== Export Complete ==="
