#!/bin/bash
echo "=== Exporting fix_molecular_mass_calculator Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_molecular_mass_calculator"
PROJECT_DIR="/home/ga/PycharmProjects/chem_mass"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/${TASK_NAME}_final.png

# Run test suite
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# --- Check Bug 1: Chlorine Data Fix ---
# Read data.py and extract Cl value
DATA_FILE="$PROJECT_DIR/chem_mass/data.py"
CL_FIXED=false
# Check if Cl is set to something around 35.45 (allowing for 35.453 etc)
if grep -qE "'Cl':\s*35\.4[0-9]*" "$DATA_FILE"; then
    CL_FIXED=true
fi
# Secondary check: test_salt_chlorine_bug PASSED
echo "$PYTEST_OUTPUT" | grep -q "test_salt_chlorine_bug PASSED" && CL_FIXED=true


# --- Check Bug 2: Multi-digit Parsing Fix ---
# Check if code handles multi-digit parsing.
# The original buggy code had:
#   if i < n and formula_part[i].isdigit():
#       count = int(formula_part[i])
#       i += 1
# A fix should involve a loop or regex to grab multiple digits.
CALC_FILE="$PROJECT_DIR/chem_mass/calculator.py"
SUB_FIXED=false

# Static check: look for a loop or a regex accumulating digits for the element count
if grep -q "while.*isdigit" "$CALC_FILE" || grep -q "re\.match" "$CALC_FILE"; then
    # We need to distinguish this from the parentheses digit parsing which was already a loop.
    # The element parsing section starts after `if char.isupper():`.
    # Let's rely primarily on the test result for robust verification.
    :
fi
# Test check: test_sucrose_multidigit_bug PASSED
echo "$PYTEST_OUTPUT" | grep -q "test_sucrose_multidigit_bug PASSED" && SUB_FIXED=true


# --- Check Bug 3: Parentheses Logic Fix ---
# Original bug: `mass += group_mass`
# Fix should be: `mass += group_mass * multiplier`
PAREN_FIXED=false
if grep -q "mass += group_mass \* multiplier" "$CALC_FILE"; then
    PAREN_FIXED=true
fi
# Test check: test_magnesium_hydroxide_parens_bug PASSED
echo "$PYTEST_OUTPUT" | grep -q "test_magnesium_hydroxide_parens_bug PASSED" && PAREN_FIXED=true


# --- Check Regression ---
# Basic tests must pass
REGRESSION_OK=false
if echo "$PYTEST_OUTPUT" | grep -q "test_simple_elements PASSED" && \
   echo "$PYTEST_OUTPUT" | grep -q "test_water PASSED"; then
    REGRESSION_OK=true
fi

# Write result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "cl_data_fixed": $CL_FIXED,
    "subscript_parsing_fixed": $SUB_FIXED,
    "parens_logic_fixed": $PAREN_FIXED,
    "regression_ok": $REGRESSION_OK
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="