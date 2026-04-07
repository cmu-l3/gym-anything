#!/bin/bash
echo "=== Exporting fix_raft_consensus Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_raft_consensus"
PROJECT_DIR="/home/ga/PycharmProjects/raft_kv"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# Run tests
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# Analyze Code Fixes via Grep (as backup to tests)
CONSENSUS_FILE="$PROJECT_DIR/raft/consensus.py"

# Bug 1: Randomized timeout check
# Look for random.uniform or random.randint or random.random
BUG1_FIXED_CODE=false
if grep -q "random\." "$CONSENSUS_FILE" 2>/dev/null; then
    BUG1_FIXED_CODE=true
fi

# Bug 2: Term check in request vote
# Look for explicit check: if msg.term < self.current_term
BUG2_FIXED_CODE=false
if grep -q "if msg\.term < self\.current_term" "$CONSENSUS_FILE" 2>/dev/null; then
    BUG2_FIXED_CODE=true
fi

# Bug 3: State transition to Follower
# Look for state assignment in append entries
BUG3_FIXED_CODE=false
if grep -q "self\.state = NodeState\.FOLLOWER" "$CONSENSUS_FILE" 2>/dev/null; then
    BUG3_FIXED_CODE=true
fi

# Check individual test pass status
TEST_TIMEOUT_PASS=false
TEST_SAFETY_PASS=false
TEST_STEPDOWN_PASS=false
TEST_STABILITY_PASS=false

echo "$PYTEST_OUTPUT" | grep -q "test_randomized_timeout PASSED" && TEST_TIMEOUT_PASS=true
echo "$PYTEST_OUTPUT" | grep -q "test_safety_outdated_term PASSED" && TEST_SAFETY_PASS=true
echo "$PYTEST_OUTPUT" | grep -q "test_candidate_steps_down PASSED" && TEST_STEPDOWN_PASS=true
echo "$PYTEST_OUTPUT" | grep -q "test_leader_election_stabilizes PASSED" && TEST_STABILITY_PASS=true

cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "test_randomized_timeout": $TEST_TIMEOUT_PASS,
    "test_safety_outdated_term": $TEST_SAFETY_PASS,
    "test_candidate_steps_down": $TEST_STEPDOWN_PASS,
    "test_leader_election_stabilizes": $TEST_STABILITY_PASS,
    "code_random_used": $BUG1_FIXED_CODE,
    "code_term_check": $BUG2_FIXED_CODE
}
EOF

echo "Pytest Exit Code: $PYTEST_EXIT_CODE"
echo "Tests Passed: $TESTS_PASSED"
echo "Timeout Fixed: $TEST_TIMEOUT_PASS"
echo "Safety Fixed: $TEST_SAFETY_PASS"
echo "Stepdown Fixed: $TEST_STEPDOWN_PASS"
echo "Stability Fixed: $TEST_STABILITY_PASS"
echo "=== Export Complete ==="