#!/bin/bash
echo "=== Exporting fix_truss_analyzer Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_truss_analyzer"
PROJECT_DIR="/home/ga/PycharmProjects/truss_analyzer"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run tests
echo "Running tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS="false"
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS="true"

echo "Pytest exit code: $PYTEST_EXIT_CODE"

# --- Analyze source for specific fixes (Heuristics) ---

# Bug 1: Area calculation
# Look for diameter/2 or radius squared
AREA_FIXED="false"
ELEMENT_FILE="$PROJECT_DIR/truss/element.py"
if grep -qE "diameter\s*/\s*2.*(\*\*|\^)\s*2" "$ELEMENT_FILE" || grep -q "radius" "$ELEMENT_FILE"; then
    AREA_FIXED="true"
fi

# Bug 2: Stiffness Matrix Rotation
# Look for correct rotation matrix structure T
# [c s 0 0]
# [-s c 0 0]
ROTATION_FIXED="false"
# This is hard to grep perfectly, relying on test_stiffness_matrix_vertical passing is better.
# But we can check if the buggy array definition changed.
# Buggy was [s, c, 0, 0] at start. Correct is [c, s, 0, 0].
if grep -q "\[c,\s*s,\s*0,\s*0\]" "$ELEMENT_FILE"; then
    ROTATION_FIXED="true"
fi

# Bug 3: Solver Assembly
# Look for += assignment
SOLVER_FILE="$PROJECT_DIR/truss/solver.py"
ASSEMBLY_FIXED="false"
if grep -qE "K\[.*\]\s*\+=\s*k_el" "$SOLVER_FILE"; then
    ASSEMBLY_FIXED="true"
fi

# --- Analyze test specific results ---
TEST_GEOMETRY_PASS="false"
TEST_ELEMENT_PASS="false"
TEST_SOLVER_PASS="false"

if echo "$PYTEST_OUTPUT" | grep -q "test_element_area PASSED"; then
    TEST_GEOMETRY_PASS="true"
fi

if echo "$PYTEST_OUTPUT" | grep -q "test_stiffness_matrix_vertical PASSED"; then
    TEST_ELEMENT_PASS="true"
fi

if echo "$PYTEST_OUTPUT" | grep -q "test_global_assembly_accumulation PASSED"; then
    TEST_SOLVER_PASS="true"
fi

# Create JSON Result
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "area_heuristic_fixed": $AREA_FIXED,
    "rotation_heuristic_fixed": $ROTATION_FIXED,
    "assembly_heuristic_fixed": $ASSEMBLY_FIXED,
    "test_geometry_pass": $TEST_GEOMETRY_PASS,
    "test_element_pass": $TEST_ELEMENT_PASS,
    "test_solver_pass": $TEST_SOLVER_PASS,
    "screenshot_path": "/tmp/task_end.png"
}
EOF

# Safe copy to tmp for copy_from_env
cp "$RESULT_FILE" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json