#!/bin/bash
echo "=== Exporting debug_media_organizer Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="debug_media_organizer"
PROJECT_DIR="/home/ga/PycharmProjects/media_organizer"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# Run tests
cd "$PROJECT_DIR" || exit 1
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# --- Check specific test passes ---
GPS_FIXED=false
if echo "$PYTEST_OUTPUT" | grep -q "test_gps_west_location PASSED" && \
   echo "$PYTEST_OUTPUT" | grep -q "test_gps_south_location PASSED"; then
    GPS_FIXED=true
fi

DATE_FIXED=false
if echo "$PYTEST_OUTPUT" | grep -q "test_date_with_dashes PASSED" && \
   echo "$PYTEST_OUTPUT" | grep -q "test_date_with_slashes PASSED"; then
    DATE_FIXED=true
fi

OVERWRITE_FIXED=false
if echo "$PYTEST_OUTPUT" | grep -q "test_no_overwrite_on_conflict PASSED"; then
    OVERWRITE_FIXED=true
fi

# --- Static Code Analysis for robustness ---

# Check 1: GPS negation logic presence
METADATA_CONTENT=$(cat "$PROJECT_DIR/organizer/metadata.py" 2>/dev/null || echo "")
GPS_LOGIC_CHECK=false
if echo "$METADATA_CONTENT" | grep -qE "if.*['\"](W|S)['\"]"; then
    # Simple check for checking W/S
    GPS_LOGIC_CHECK=true
fi
if echo "$METADATA_CONTENT" | grep -qE "\-1"; then
    # Check for multiplying by -1 or returning negative
    GPS_LOGIC_CHECK=true
fi

# Check 2: Safe move existence check
CORE_CONTENT=$(cat "$PROJECT_DIR/organizer/core.py" 2>/dev/null || echo "")
SAFE_MOVE_CHECK=false
if echo "$CORE_CONTENT" | grep -q "os.path.exists"; then
    # They should be checking if dest exists
    SAFE_MOVE_CHECK=true
fi
if echo "$CORE_CONTENT" | grep -qE "while.*exists|counter \+= 1|_\d+"; then
    # Look for renaming loop or logic
    SAFE_MOVE_CHECK=true
fi

cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "gps_tests_passed": $GPS_FIXED,
    "date_tests_passed": $DATE_FIXED,
    "overwrite_tests_passed": $OVERWRITE_FIXED,
    "gps_logic_heuristic": $GPS_LOGIC_CHECK,
    "safe_move_heuristic": $SAFE_MOVE_CHECK
}
EOF

echo "Pytest: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "GPS Fixed: $GPS_FIXED"
echo "Date Fixed: $DATE_FIXED"
echo "Overwrite Fixed: $OVERWRITE_FIXED"
echo "=== Export Complete ==="