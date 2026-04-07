#!/bin/bash
echo "=== Exporting fix_flight_planner Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_flight_planner"
PROJECT_DIR="/home/ga/PycharmProjects/flight_planner"
RESULT_FILE="/tmp/flight_planner_result.json"
TASK_START=$(cat /tmp/flight_planner_start_ts 2>/dev/null || echo "0")

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/flight_planner_final.png 2>/dev/null || true

# 2. Run Tests
# Run pytest as 'ga' user inside the project directory
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

# 3. Parse Test Results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

ALL_TESTS_PASS="false"
if [ "$PYTEST_EXIT_CODE" -eq 0 ] && [ "$TESTS_TOTAL" -gt 0 ]; then
    ALL_TESTS_PASS="true"
fi

# 4. Check for Specific Logic Fixes (Regex Checks)

# GEO FIX CHECK: Look for Earth radius change or conversion
GEO_FILE="$PROJECT_DIR/planner/geo.py"
GEO_FIXED_DISTANCE="false"
# Check for 3440 (NM radius) or division by 1.852
if grep -q "3440" "$GEO_FILE" 2>/dev/null || grep -q "1.852" "$GEO_FILE" 2>/dev/null; then
    GEO_FIXED_DISTANCE="true"
fi

GEO_FIXED_BEARING="false"
# Check for atan2 usage
if grep -q "atan2" "$GEO_FILE" 2>/dev/null; then
    GEO_FIXED_BEARING="true"
fi

# WIND FIX CHECK: Look for subtraction of wind component
WIND_FILE="$PROJECT_DIR/planner/wind.py"
WIND_FIXED="false"
# Check for subtraction
if grep -q "true_airspeed - wind_component" "$WIND_FILE" 2>/dev/null; then
    WIND_FIXED="true"
elif grep -q "true_airspeed + wind_component" "$WIND_FILE" 2>/dev/null; then
    # If they kept +, check if they inverted the angle or component sign
    if grep -q "\-.*wind_speed" "$WIND_FILE" 2>/dev/null; then
        WIND_FIXED="true"
    fi
fi

# FUEL FIX CHECK: Look for division by 60
FUEL_FILE="$PROJECT_DIR/planner/fuel.py"
FUEL_FIXED="false"
if grep -q "/ 60" "$FUEL_FILE" 2>/dev/null || grep -q "/60" "$FUEL_FILE" 2>/dev/null; then
    FUEL_FIXED="true"
fi
# Alternative: check if they convert minutes to hours
if grep -q "reserve_minutes / 60" "$FUEL_FILE" 2>/dev/null; then
    FUEL_FIXED="true"
fi

# 5. Check Specific Test Passes (in case regex fails)
TEST_DISTANCE_PASS=$(echo "$PYTEST_OUTPUT" | grep -q "test_distance_jfk_lhr_nm PASSED" && echo "true" || echo "false")
TEST_BEARING_PASS=$(echo "$PYTEST_OUTPUT" | grep -q "test_bearing_sw_quadrant PASSED" && echo "true" || echo "false")
TEST_WIND_PASS=$(echo "$PYTEST_OUTPUT" | grep -q "test_ground_speed_headwind PASSED" && echo "true" || echo "false")
TEST_FUEL_PASS=$(echo "$PYTEST_OUTPUT" | grep -q "test_reserve_fuel_45min PASSED" && echo "true" || echo "false")

# 6. Generate JSON Result
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "geo_fixed_distance_code": $GEO_FIXED_DISTANCE,
    "geo_fixed_bearing_code": $GEO_FIXED_BEARING,
    "wind_fixed_code": $WIND_FIXED,
    "fuel_fixed_code": $FUEL_FIXED,
    "test_distance_pass": $TEST_DISTANCE_PASS,
    "test_bearing_pass": $TEST_BEARING_PASS,
    "test_wind_pass": $TEST_WIND_PASS,
    "test_fuel_pass": $TEST_FUEL_PASS,
    "screenshot_path": "/tmp/flight_planner_final.png"
}
EOF

# Safe copy to tmp (verifier reads from here)
cp "$RESULT_FILE" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json