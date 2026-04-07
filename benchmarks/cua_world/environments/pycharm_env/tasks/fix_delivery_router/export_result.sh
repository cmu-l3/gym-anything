#!/bin/bash
echo "=== Exporting fix_delivery_router Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_delivery_router"
PROJECT_DIR="/home/ga/PycharmProjects/route_optimizer"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Run Test Suite
echo "Running tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# 3. Code Inspection (Grepping for fixes)

# Bug 1: Check for radians conversion in distance.py
DISTANCE_FILE="$PROJECT_DIR/routing/distance.py"
BUG1_FIXED=false
# Look for 'radians(' or map(radians...
if grep -q "radians" "$DISTANCE_FILE"; then
    BUG1_FIXED=true
fi
# Double check: if accuracy test passed, it's likely fixed regardless of implementation style
if echo "$PYTEST_OUTPUT" | grep -q "test_haversine_accuracy PASSED"; then
    BUG1_FIXED=true
fi

# Bug 2: Check for visited set update in solver.py
SOLVER_FILE="$PROJECT_DIR/routing/solver.py"
BUG2_FIXED=false
# Check if 'visited.add' or 'visited.append' is present (and not commented out)
if grep -q "visited.add" "$SOLVER_FILE"; then
     BUG2_FIXED=true
fi
# Also check if we check membership 'in visited'
if grep -q "in visited" "$SOLVER_FILE"; then
     # Need both for logic to hold
     : 
fi
# Rely on test result for definitive proof
if echo "$PYTEST_OUTPUT" | grep -q "test_solver_visits_all_nodes PASSED" && \
   echo "$PYTEST_OUTPUT" | grep -q "test_solver_no_duplicates PASSED"; then
    BUG2_FIXED=true
fi

# Bug 3: Check for return trip in calculate_total_distance
BUG3_FIXED=false
# If logic adds dist(last, first)
if echo "$PYTEST_OUTPUT" | grep -q "test_return_to_depot_distance PASSED"; then
    BUG3_FIXED=true
fi

# 4. Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_radians_fixed": $BUG1_FIXED,
    "bug2_solver_logic_fixed": $BUG2_FIXED,
    "bug3_return_leg_fixed": $BUG3_FIXED,
    "screenshot_path": "/tmp/${TASK_NAME}_end_screenshot.png"
}
EOF

echo "Export completed. Results:"
cat "$RESULT_FILE"