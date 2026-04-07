#!/bin/bash
echo "=== Exporting fix_traffic_intersection_sim Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_traffic_intersection_sim"
PROJECT_DIR="/home/ga/PycharmProjects/micro_sim"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Tests
echo "Running tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# 2. Run Simulation Scenario
echo "Running simulation..."
SIM_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 main.py 2>&1")

# Parse Simulation Output
COLLISIONS_COUNT=$(echo "$SIM_OUTPUT" | grep "Collisions:" | awk '{print $2}' || echo "999")
VIOLATIONS_COUNT=$(echo "$SIM_OUTPUT" | grep "Signal Violations:" | awk '{print $2}' || echo "999")
VEHICLES_COMPLETED=$(echo "$SIM_OUTPUT" | grep "Vehicles Completed:" | awk '{print $2}' || echo "0")

# 3. Static Code Analysis (Fix verification)
# Bug 1 Fix: Check if inequality is fixed in vehicle.py
BUG1_FIXED=false
if grep -q "time_to_arrival.*>.*REQUIRED_GAP" "$PROJECT_DIR/sim/vehicle.py" || \
   grep -q "time_to_arrival.*>=.*REQUIRED_GAP" "$PROJECT_DIR/sim/vehicle.py" || \
   grep -q "REQUIRED_GAP.*<.*time_to_arrival" "$PROJECT_DIR/sim/vehicle.py"; then
    BUG1_FIXED=true
fi

# Bug 2 Fix: Check for AMBER state usage in signal.py
BUG2_FIXED=false
if grep -q "SignalState.AMBER" "$PROJECT_DIR/sim/signal.py"; then
    # Must assign AMBER state inside update loop
    if grep -q "self.state.*=.*SignalState.AMBER" "$PROJECT_DIR/sim/signal.py"; then
        BUG2_FIXED=true
    fi
fi

# Bug 3 Fix: Check loop range in intersection.py
BUG3_FIXED=false
# Should NOT match "range(len(self.queue) - 1)"
# Should match "range(len(self.queue))"
if grep -q "range(len(self.queue))" "$PROJECT_DIR/sim/intersection.py" && \
   ! grep -q "range(len(self.queue).*-\s*1)" "$PROJECT_DIR/sim/intersection.py"; then
    BUG3_FIXED=true
fi

# Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "sim_collisions": $COLLISIONS_COUNT,
    "sim_violations": $VIOLATIONS_COUNT,
    "sim_throughput": $VEHICLES_COMPLETED,
    "bug1_fixed_code": $BUG1_FIXED,
    "bug2_fixed_code": $BUG2_FIXED,
    "bug3_fixed_code": $BUG3_FIXED
}
EOF

# Move to correct location with permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="