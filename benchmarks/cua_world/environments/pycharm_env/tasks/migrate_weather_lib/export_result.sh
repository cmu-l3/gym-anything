#!/bin/bash
# Export script for migrate_weather_lib task

echo "=== Exporting migrate_weather_lib result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="migrate_weather_lib"
PROJECT_DIR="/home/ga/PycharmProjects/weather_analysis"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Tests and Capture Output
echo "Running tests..."
# We expect syntax errors initially, so we capture stderr too
# Run as user ga
PYTEST_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

echo "Pytest exit code: $PYTEST_EXIT_CODE"

# Parse test results
# Look for "X passed, Y failed" or "collected X items"
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -oP '(\d+) passed' | head -1 | awk '{print $1}' || echo "0")
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -oP '(\d+) failed' | head -1 | awk '{print $1}' || echo "0")
TESTS_ERROR=$(echo "$PYTEST_OUTPUT" | grep -oP '(\d+) error' | head -1 | awk '{print $1}' || echo "0")

# If syntax errors prevent collection, these might be empty
if [ -z "$TESTS_PASSED" ]; then TESTS_PASSED=0; fi
if [ -z "$TESTS_FAILED" ]; then TESTS_FAILED=0; fi
if [ -z "$TESTS_ERROR" ]; then TESTS_ERROR=0; fi

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED + TESTS_ERROR))

# 2. Check for Python 2 Artifacts (Source Inspection)
# We want to confirm they actually fixed the code, not just deleted it or mocked it out.
ARTIFACTS_FOUND="false"
ARTIFACT_DETAILS=""

# Function to check for pattern
check_artifact() {
    pattern=$1
    file_pattern=$2
    if grep -r "$pattern" "$PROJECT_DIR/weather" --include="$file_pattern"; then
        ARTIFACTS_FOUND="true"
        ARTIFACT_DETAILS="$ARTIFACT_DETAILS Found '$pattern' in $file_pattern;"
    fi
}

check_artifact 'print "' "*.py"
check_artifact '.iteritems()' "*.py"
check_artifact '.has_key(' "*.py"
check_artifact 'unicode(' "*.py"
check_artifact 'basestring' "*.py"
check_artifact 'raw_input(' "*.py"
check_artifact 'xrange(' "*.py"
check_artifact 'except .*,.*:' "*.py"

# Check for specific Python 3 fixes
# parser.py: print()
HAS_PRINT_FUNC=$(grep 'print(' "$PROJECT_DIR/weather/parser.py" > /dev/null && echo "true" || echo "false")
# parser.py: items()
HAS_ITEMS=$(grep '\.items()' "$PROJECT_DIR/weather/parser.py" > /dev/null && echo "true" || echo "false")
# parser.py: 'key' in dict
HAS_IN_DICT=$(grep 'in row' "$PROJECT_DIR/weather/parser.py" > /dev/null && echo "true" || echo "false")
# statistics.py: reduce import
HAS_REDUCE_IMPORT=$(grep 'from functools import reduce' "$PROJECT_DIR/weather/statistics.py" > /dev/null && echo "true" || echo "false")
# report.py: except as
HAS_EXCEPT_AS=$(grep 'except .* as ' "$PROJECT_DIR/weather/report.py" > /dev/null && echo "true" || echo "false")
# utils.py: input()
HAS_INPUT=$(grep 'input(' "$PROJECT_DIR/weather/utils.py" > /dev/null && echo "true" || echo "false")

# 3. Anti-Gaming: Check File Modifications
# Verify that source files were modified after task start
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
FILES_MODIFIED="false"
MOD_COUNT=0

for f in "$PROJECT_DIR/weather/"*.py; do
    F_MTIME=$(stat -c %Y "$f")
    if [ "$F_MTIME" -gt "$TASK_START" ]; then
        MOD_COUNT=$((MOD_COUNT + 1))
    fi
done

if [ "$MOD_COUNT" -ge 3 ]; then
    FILES_MODIFIED="true"
fi

# 4. Construct JSON
# Use Python to generate JSON to avoid escaping issues
python3 -c "
import json
import os
import sys

output = {
    'pytest_exit_code': $PYTEST_EXIT_CODE,
    'tests_passed': int('$TESTS_PASSED'),
    'tests_failed': int('$TESTS_FAILED'),
    'tests_error': int('$TESTS_ERROR'),
    'total_tests': int('$TOTAL_TESTS'),
    'artifacts_found': '$ARTIFACTS_FOUND' == 'true',
    'artifact_details': '$ARTIFACT_DETAILS',
    'files_modified': '$FILES_MODIFIED' == 'true',
    'mod_count': $MOD_COUNT,
    'specific_fixes': {
        'print_func': '$HAS_PRINT_FUNC' == 'true',
        'items_method': '$HAS_ITEMS' == 'true',
        'reduce_import': '$HAS_REDUCE_IMPORT' == 'true',
        'except_as': '$HAS_EXCEPT_AS' == 'true',
        'input_func': '$HAS_INPUT' == 'true'
    }
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(output, f, indent=2)
"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="