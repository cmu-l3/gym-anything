#!/bin/bash
echo "=== Exporting fix_basketball_stats Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/league_builder"
RESULT_FILE="/tmp/fix_basketball_stats_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Run tests and capture output
echo "Running tests..."
# Run pytest as 'ga' user
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

# 3. Analyze Test Results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

# Specific Bug Verifications based on test names
BUG1_FIXED="false"
if echo "$PYTEST_OUTPUT" | grep -q "test_player_stats_isolation PASSED"; then
    BUG1_FIXED="true"
fi

BUG2_FIXED="false"
if echo "$PYTEST_OUTPUT" | grep -q "test_standings_head_to_head_tiebreaker PASSED"; then
    BUG2_FIXED="true"
fi

BUG3_FIXED="false"
if echo "$PYTEST_OUTPUT" | grep -q "test_streak_calculation_reset_on_loss PASSED"; then
    BUG3_FIXED="true"
fi

# 4. Check Code Content (Anti-Gaming / Static Analysis)
# Ensure they actually modified the logic and didn't just hardcode tests
# Check Bug 1: Look for dictionary instantiation inside register_player or copy()
STATS_ENGINE_CONTENT=$(cat "$PROJECT_DIR/league/stats_engine.py" 2>/dev/null)

CODE_CHECK_1="false"
# Should see something like `stats={...}` or `.copy()` inside the function, not referencing the shared one
if echo "$STATS_ENGINE_CONTENT" | grep -q "stats\s*=\s*{" || echo "$STATS_ENGINE_CONTENT" | grep -q "\.copy()"; then
    CODE_CHECK_1="true"
fi

CODE_CHECK_3="false"
# Should see a reset logic like `streak = 0` inside the loop
if echo "$STATS_ENGINE_CONTENT" | grep -q "streak\s*=\s*0"; then
    CODE_CHECK_3="true"
fi

# 5. Create JSON Result
cat > "$RESULT_FILE" << EOF
{
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "total_tests": $TOTAL_TESTS,
    "bug1_fixed_test": $BUG1_FIXED,
    "bug2_fixed_test": $BUG2_FIXED,
    "bug3_fixed_test": $BUG3_FIXED,
    "code_check_mutable_default_removed": $CODE_CHECK_1,
    "code_check_streak_reset_added": $CODE_CHECK_3,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete. Result:"
cat "$RESULT_FILE"