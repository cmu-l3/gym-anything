#!/bin/bash
echo "=== Exporting fix_3d_printer_slicer result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/py_slicer"
RESULT_FILE="/tmp/fix_3d_printer_slicer_result.json"
TASK_START=$(cat /tmp/fix_3d_printer_slicer_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run tests
cd "$PROJECT_DIR"
PYTEST_OUTPUT=$(su - ga -c "python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

ALL_TESTS_PASS="false"
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS="true"

# Check for specific bug fixes via test names
BUG1_FIXED="false"
BUG2_FIXED="false"
BUG3_FIXED="false"

echo "$PYTEST_OUTPUT" | grep -q "test_horizontal_intersection PASSED" && BUG1_FIXED="true"
echo "$PYTEST_OUTPUT" | grep -q "test_layer_count PASSED" && BUG2_FIXED="true"
echo "$PYTEST_OUTPUT" | grep -q "test_perimeter_closure PASSED" && BUG3_FIXED="true"

# Check source code for specific patterns (Anti-gaming / Robustness)
ENGINE_FILE="$PROJECT_DIR/py_slicer/engine.py"
SOURCE_CHECK_PASSED="false"

# Check if ZeroDivisionError guard exists (or parallel edge check)
if grep -q "abs.*z2.*-.*z1" "$ENGINE_FILE" || grep -q "z2.*==.*z1" "$ENGINE_FILE"; then
    # Loose check for some attempt to handle z2=z1
    SOURCE_CHECK_PASSED="true"
fi

cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_total": $TESTS_TOTAL,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_fixed": $BUG1_FIXED,
    "bug2_fixed": $BUG2_FIXED,
    "bug3_fixed": $BUG3_FIXED,
    "source_check_passed": $SOURCE_CHECK_PASSED,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="