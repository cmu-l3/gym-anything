#!/bin/bash
echo "=== Exporting fix_astro_coordinates Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_astro_coordinates"
PROJECT_DIR="/home/ga/PycharmProjects/astro_coords"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Final screenshot
take_screenshot /tmp/task_final.png

# Run tests
echo "Running tests..."
# Install requirements if needed (agent might have added new ones, though they shouldn't)
# su - ga -c "pip install -r $PROJECT_DIR/requirements.txt" 2>/dev/null

# Run pytest
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

echo "Pytest exit code: $PYTEST_EXIT_CODE"

# Parse Test Results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && [ "$TESTS_TOTAL" -gt 0 ] && ALL_TESTS_PASS=true

# --- Code Verification (Regex checks on source files) ---

# Bug 1: NGP Declination radians conversion
# Look for math.radians(27.12825) or similar variable assignment
TRANSFORMS_FILE="$PROJECT_DIR/coords/transforms.py"
BUG1_FIXED=false
if grep -q "math.radians(27.12825)" "$TRANSFORMS_FILE" || \
   grep -q "math.radians(delta_ngp)" "$TRANSFORMS_FILE"; then
    BUG1_FIXED=true
fi
# Also check if test passed
echo "$PYTEST_OUTPUT" | grep -q "test_equatorial_to_galactic_sirius PASSED" && BUG1_FIXED=true

# Bug 2: atan2 arguments order
# Look for atan2(y, x) pattern where y=sin(ha)...
# Original buggy: atan2(x, y)
# Correct: atan2(y, x)
# Since variable names might change, relying on the test is safer, but we can look for the pattern change
BUG2_FIXED=false
echo "$PYTEST_OUTPUT" | grep -q "test_equatorial_to_horizontal_vega PASSED" && BUG2_FIXED=true

# Bug 3: Angular separation subtraction
SEPARATION_FILE="$PROJECT_DIR/coords/separation.py"
BUG3_FIXED=false
# Check for minus sign in the cosine argument: cos(ra1 - ra2) or cos(ra1-ra2)
if grep -q "cos(ra1.*-.*ra2)" "$SEPARATION_FILE" || \
   grep -q "cos(ra2.*-.*ra1)" "$SEPARATION_FILE"; then
    BUG3_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_separation_close_stars PASSED" && BUG3_FIXED=true

# Bug 4: HMS Seconds division
CONVERSIONS_FILE="$PROJECT_DIR/coords/conversions.py"
BUG4_FIXED=false
# Check for division by 3600 or equivalent logic
if grep -q "s / 3600" "$CONVERSIONS_FILE" || \
   grep -q "s/3600" "$CONVERSIONS_FILE"; then
    BUG4_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_parse_hms_sirius PASSED" && BUG4_FIXED=true

# Regression Check
# Ensure basic tests still pass
NO_REGRESSION=false
if echo "$PYTEST_OUTPUT" | grep -q "test_deg_to_rad PASSED" && \
   echo "$PYTEST_OUTPUT" | grep -q "test_rad_to_deg PASSED" && \
   echo "$PYTEST_OUTPUT" | grep -q "test_galactic_to_equatorial_vega PASSED"; then
    NO_REGRESSION=true
fi

# Write JSON result
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_fixed": $BUG1_FIXED,
    "bug2_fixed": $BUG2_FIXED,
    "bug3_fixed": $BUG3_FIXED,
    "bug4_fixed": $BUG4_FIXED,
    "no_regression": $NO_REGRESSION,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permission fix
chmod 666 "$RESULT_FILE"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="