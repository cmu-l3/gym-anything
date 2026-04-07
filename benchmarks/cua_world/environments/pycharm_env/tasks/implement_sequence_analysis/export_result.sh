#!/bin/bash
echo "=== Exporting Sequence Analysis Results ==="

source /workspace/scripts/task_utils.sh

TASK_DIR="/home/ga/PycharmProjects/seq_toolkit"
RESULT_FILE="/tmp/task_result.json"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for anti-gaming (test tampering)
TESTS_TAMPERED="false"
if ! md5sum -c /tmp/tests_checksum.md5 --status 2>/dev/null; then
    TESTS_TAMPERED="true"
    echo "WARNING: Test files have been modified!"
fi

# 3. Run tests and capture output
echo "Running tests..."
cd "$TASK_DIR"
# We run with --tb=short to get concise output for parsing
PYTEST_OUT=$(python3 -m pytest tests/ -v --tb=short 2>&1)
PYTEST_EXIT_CODE=$?

# 4. Parse Test Results
TESTS_PASSED=$(echo "$PYTEST_OUT" | grep -c " PASSED" || echo "0")
TESTS_FAILED=$(echo "$PYTEST_OUT" | grep -c " FAILED" || echo "0")
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

# 5. Check for remaining stubs (NotImplementedError)
# We count how many NotImplementedErrors are still raised in source code
# We check the SOURCE files, not the output, to see if the user removed the raises.
STUBS_REMAINING=$(grep -r "raise NotImplementedError" sequence/ | wc -l)

# 6. Capture individual passed tests for granular scoring
PASSED_TEST_NAMES=$(echo "$PYTEST_OUT" | grep " PASSED" | awk '{print $2}' | cut -d: -f2 | tr '\n' ',')

# 7. Create JSON payload
# We use python to safely generate JSON
python3 -c "
import json
import os

result = {
    'tests_passed': int('$TESTS_PASSED'),
    'tests_failed': int('$TESTS_FAILED'),
    'total_tests': int('$TOTAL_TESTS'),
    'pytest_exit_code': int('$PYTEST_EXIT_CODE'),
    'tests_tampered': '$TESTS_TAMPERED' == 'true',
    'stubs_remaining_count': int('$STUBS_REMAINING'),
    'passed_test_names': '$PASSED_TEST_NAMES'.split(',')[:-1],  # Remove trailing empty string
    'task_start_time': int('$START_TIME'),
    'timestamp': '$(date -Iseconds)'
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
"

# 8. Set permissions
chmod 666 "$RESULT_FILE"
cp "$RESULT_FILE" /tmp/seq_analysis_result.json
chmod 666 /tmp/seq_analysis_result.json

echo "Results exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="