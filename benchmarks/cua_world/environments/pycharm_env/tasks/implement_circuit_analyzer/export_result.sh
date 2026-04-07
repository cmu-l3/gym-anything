#!/bin/bash
echo "=== Exporting circuit_analyzer results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/circuit_analyzer"
RESULT_FILE="/tmp/circuit_analyzer_result.json"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Verify PyCharm was running
PYCHARM_RUNNING=$(pgrep -f "pycharm" > /dev/null && echo "true" || echo "false")

# Verify tests were not tampered with
sha256sum $PROJECT_DIR/tests/*.py > /tmp/test_hashes_final.txt
TESTS_TAMPERED="false"
if ! diff /tmp/test_hashes_initial.txt /tmp/test_hashes_final.txt > /dev/null; then
    TESTS_TAMPERED="true"
    echo "WARNING: Test files modified!"
fi

# Run tests and capture detailed output
cd "$PROJECT_DIR"
# We run pytest with -v and capture the output to parse it
# We use sudo to ensure we can run it even if permissions are wonky, but prefer ga user
PYTEST_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/ -v" 2>&1)
PYTEST_EXIT_CODE=$?

# Count passes/fails from output
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED")
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED")
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

# Extract specific test results for finer scoring
PASS_COMPONENTS=$(echo "$PYTEST_OUTPUT" | grep "test_components.py" | grep -c " PASSED")
PASS_NETWORKS=$(echo "$PYTEST_OUTPUT" | grep "test_networks.py" | grep -c " PASSED")
PASS_AC=$(echo "$PYTEST_OUTPUT" | grep "test_ac_analysis.py" | grep -c " PASSED")
PASS_ANALYSIS=$(echo "$PYTEST_OUTPUT" | grep "test_analysis.py" | grep -c " PASSED")

# Check for hardcoding in implementation files
# We look for "return [number]" without any math logic, which is a common cheat
HARDCODING_DETECTED="false"
for f in "circuits/components.py" "circuits/networks.py" "circuits/ac_analysis.py" "circuits/analysis.py"; do
    if [ -f "$f" ]; then
        # suspicious if return follows a literal number directly, though naive
        # Better check: look for NotImplementedError still present
        if grep -q "raise NotImplementedError" "$f"; then
            # Not hardcoding, but incomplete. We track incomplete separately via test failures.
            pass
        fi
    fi
done

# Prepare JSON result
cat > "$RESULT_FILE" << EOF
{
    "pycharm_running": $PYCHARM_RUNNING,
    "tests_tampered": $TESTS_TAMPERED,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "total_tests": $TOTAL_TESTS,
    "pass_breakdown": {
        "components": $PASS_COMPONENTS,
        "networks": $PASS_NETWORKS,
        "ac_analysis": $PASS_AC,
        "analysis": $PASS_ANALYSIS
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy to /tmp for verification
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. passed=$TESTS_PASSED failed=$TESTS_FAILED tampered=$TESTS_TAMPERED"